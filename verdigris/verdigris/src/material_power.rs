//! Bounded, double-precision electrical solve. No game objects or persistent
//! handles cross this boundary; DM owns topology, material state and energy.
use eyre::{Result, bail};

pub struct Solution {
    pub voltages: Vec<f64>,
    pub residual: f64,
    pub iterations: usize,
}

pub fn solve(edges: &[(usize, usize, f64)], rhs: &[f64], initial: &[f64]) -> Result<Solution> {
    let n = rhs.len();
    if n == 0 || n > 32768 || edges.len() > 131072 || initial.len() != n {
        bail!("invalid material power graph dimensions");
    }
    if rhs.iter().chain(initial).any(|v| !v.is_finite()) {
        bail!("non-finite material power input");
    }
    let mut diagonal = vec![0.0; n];
    for &(a, b, r) in edges {
        if a >= n || b >= n || a == b || !r.is_finite() || r <= 0.0 {
            bail!("invalid material power edge");
        }
        diagonal[a] += 1.0 / r;
        diagonal[b] += 1.0 / r;
    }
    let multiply = |input: &[f64], output: &mut [f64]| {
        output.fill(0.0);
        for &(a, b, resistance) in edges {
            let current = (input[a] - input[b]) / resistance;
            if a != 0 {
                output[a] += current;
            }
            if b != 0 {
                output[b] -= current;
            }
        }
    };
    let mut voltage = initial.to_vec();
    voltage[0] = 0.0;
    let mut product = vec![0.0; n];
    multiply(&voltage, &mut product);
    let mut residual = vec![0.0; n];
    let mut direction = vec![0.0; n];
    let mut squared = 0.0;
    let mut rz = 0.0;
    let mut norm = 0.0;
    for i in 1..n {
        if diagonal[i] == 0.0 {
            if rhs[i] != 0.0 {
                bail!("load on disconnected material power vertex");
            }
            voltage[i] = 0.0;
            continue;
        }
        residual[i] = rhs[i] - product[i];
        direction[i] = residual[i] / diagonal[i];
        squared += residual[i] * residual[i];
        norm += rhs[i] * rhs[i];
        rz += residual[i] * direction[i];
    }
    let target = (norm * 1e-12).max(1e-14);
    let limit = (n * 2).min(4096).min(12_000_000 / edges.len().max(1));
    let mut iterations = 0;
    while squared > target && iterations < limit {
        iterations += 1;
        multiply(&direction, &mut product);
        let denominator: f64 = direction
            .iter()
            .zip(&product)
            .skip(1)
            .map(|(a, b)| a * b)
            .sum();
        if !denominator.is_finite() || denominator <= 0.0 {
            break;
        }
        let alpha = rz / denominator;
        let mut next_rz = 0.0;
        squared = 0.0;
        for i in 1..n {
            voltage[i] += alpha * direction[i];
            residual[i] -= alpha * product[i];
            squared += residual[i] * residual[i];
            if diagonal[i] > 0.0 {
                next_rz += residual[i] * residual[i] / diagonal[i];
            }
        }
        let beta = next_rz / rz.max(f64::MIN_POSITIVE);
        for i in 1..n {
            direction[i] = if diagonal[i] > 0.0 {
                residual[i] / diagonal[i] + beta * direction[i]
            } else {
                0.0
            };
        }
        rz = next_rz;
    }
    if !squared.is_finite()
        || voltage
            .iter()
            .any(|v| !v.is_finite() || v.abs() > f32::MAX as f64)
    {
        bail!("non-finite material power solution");
    }
    Ok(Solution {
        voltages: voltage,
        residual: squared.sqrt(),
        iterations,
    })
}

#[cfg(target_arch = "x86")]
mod ffi {
    use byondapi::prelude::*;
    use eyre::{Result, bail};

    fn numbers(value: ByondValue) -> Result<Vec<f64>> {
        value
            .get_list_values()?
            .into_iter()
            .map(|v| {
                Ok(if v.is_null() {
                    0.0
                } else {
                    f64::from(v.get_number()?)
                })
            })
            .collect()
    }

    #[byondapi::bind("/proc/solve_material_power_graph")]
    #[auxmacros::panic_safe]
    fn solve_material_power_graph(
        topology: ByondValue,
        loads: ByondValue,
        warm: ByondValue,
    ) -> Result<ByondValue> {
        let flat = numbers(topology)?;
        let rhs = numbers(loads)?;
        let initial = numbers(warm)?;
        if flat.len() % 3 != 0 {
            bail!("material power edges must be triples");
        }
        let mut edges = Vec::with_capacity(flat.len() / 3);
        for edge in flat.chunks_exact(3) {
            if edge[0] < 1.0 || edge[1] < 1.0 || edge[0].fract() != 0.0 || edge[1].fract() != 0.0 {
                bail!("material power indices must be positive integers");
            }
            edges.push((edge[0] as usize - 1, edge[1] as usize - 1, edge[2]));
        }
        let solution = super::solve(&edges, &rhs, &initial)?;
        let mut output = Vec::with_capacity(rhs.len() + 2);
        output.push(ByondValue::from(solution.residual as f32));
        output.push(ByondValue::from(solution.iterations as f32));
        output.extend(
            solution
                .voltages
                .into_iter()
                .map(|v| ByondValue::from(v as f32)),
        );
        let result = ByondValue::new_list()?;
        result.write_list(&output)?;
        Ok(result)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn branches_loops_and_warm_start() {
        let edges = [(0, 1, 1.0), (1, 3, 1.0), (0, 2, 1.0), (2, 3, 1.0)];
        let rhs = [10.0, 0.0, 0.0, -10.0];
        let solution = solve(&edges, &rhs, &[0.0; 4]).unwrap();
        assert!(solution.residual < 1e-8);
        for &(a, b, r) in &edges {
            assert!(((solution.voltages[a] - solution.voltages[b]) / r - 5.0).abs() < 1e-8);
        }
        assert_eq!(
            solve(&edges, &rhs, &solution.voltages).unwrap().iterations,
            0
        );
    }

    #[test]
    fn station_scale_mesh_converges() {
        let width = 40;
        let n = width * width;
        let mut edges = Vec::new();
        for y in 0..width {
            for x in 0..width {
                let a = y * width + x;
                if x + 1 < width {
                    edges.push((a, a + 1, 0.0001));
                }
                if y + 1 < width {
                    edges.push((a, a + width, 0.0002));
                }
            }
        }
        let mut rhs = vec![-1.0; n];
        rhs[0] = (n - 1) as f64;
        let result = solve(&edges, &rhs, &vec![0.0; n]).unwrap();
        assert!(result.residual < 0.0001, "{}", result.residual);
        assert!(result.iterations < n);
        assert!(result.voltages.iter().all(|v| v.is_finite()));
    }

    #[test]
    fn malformed_inputs_are_rejected() {
        assert!(solve(&[(0, 2, 1.0)], &[0.0; 2], &[0.0; 2]).is_err());
        assert!(solve(&[(0, 1, -1.0)], &[0.0; 2], &[0.0; 2]).is_err());
        assert!(solve(&[(0, 1, f64::NAN)], &[0.0; 2], &[0.0; 2]).is_err());
        assert!(solve(&[], &[0.0, 1.0], &[0.0; 2]).is_err());
    }
}
