// Stock share-value chart — structured SVG bar chart for the displayValues
// admin viewer. Replaces the legacy plotBarGraph HTML table with proper SVG.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, LabeledList, Section } from 'tgui-core/components';
import { EmptyState } from './common/EmptyState';

type Data = {
  stock_name: string;
  points: number[];
};

const WIDTH = 600;
const HEIGHT = 400;
const PADDING = { top: 16, right: 16, bottom: 28, left: 56 };

export const StockChart = () => {
  const { data } = useBackend<Data>();
  const { stock_name, points } = data;
  if (points.length === 0) {
    return (
      <Window width={680} height={500} title={`Share Value: ${stock_name}`}>
        <Window.Content>
          <Section title={`${stock_name} — share value`}>
            <EmptyState>No data points yet.</EmptyState>
          </Section>
        </Window.Content>
      </Window>
    );
  }
  const minVal = Math.min(...points, 0);
  const maxVal = Math.max(...points);
  const range = maxVal - minVal || 1;
  const innerW = WIDTH - PADDING.left - PADDING.right;
  const innerH = HEIGHT - PADDING.top - PADDING.bottom;
  const barWidth = innerW / points.length;
  const yAxisTicks = 5;
  const tickValues = Array.from(
    { length: yAxisTicks + 1 },
    (_, i) => minVal + (range * i) / yAxisTicks,
  );
  return (
    <Window width={720} height={560} title={`Share Value: ${stock_name}`}>
      <Window.Content>
        <Section title={`${stock_name} share value per share`}>
          <LabeledList>
            <LabeledList.Item label="Latest">
              {Math.round(points[points.length - 1])}
            </LabeledList.Item>
            <LabeledList.Item label="Min">
              {Math.round(minVal)}
            </LabeledList.Item>
            <LabeledList.Item label="Max">
              {Math.round(maxVal)}
            </LabeledList.Item>
            <LabeledList.Item label="Samples">{points.length}</LabeledList.Item>
          </LabeledList>
          <Box mt={1}>
            <svg
              width={WIDTH}
              height={HEIGHT}
              viewBox={`0 0 ${WIDTH} ${HEIGHT}`}
              style={{ background: '#000' }}
            >
              {tickValues.map((v, i) => {
                const y =
                  PADDING.top + innerH - ((v - minVal) / range) * innerH;
                return (
                  <g key={i}>
                    <line
                      x1={PADDING.left}
                      y1={y}
                      x2={WIDTH - PADDING.right}
                      y2={y}
                      stroke="#0a4"
                      strokeWidth={1}
                      strokeDasharray="2 4"
                    />
                    <text
                      x={PADDING.left - 6}
                      y={y + 4}
                      fill="#0f0"
                      fontSize={11}
                      textAnchor="end"
                      fontFamily="monospace"
                    >
                      {Math.round(v)}
                    </text>
                  </g>
                );
              })}
              {points.map((v, i) => {
                const x = PADDING.left + i * barWidth;
                const h = ((v - minVal) / range) * innerH;
                const y = PADDING.top + innerH - h;
                return (
                  <rect
                    key={i}
                    x={x + 1}
                    y={y}
                    width={Math.max(1, barWidth - 2)}
                    height={Math.max(1, h)}
                    fill="#39f"
                  />
                );
              })}
              <line
                x1={PADDING.left}
                y1={PADDING.top + innerH}
                x2={WIDTH - PADDING.right}
                y2={PADDING.top + innerH}
                stroke="#0f0"
                strokeWidth={1}
              />
              <line
                x1={PADDING.left}
                y1={PADDING.top}
                x2={PADDING.left}
                y2={PADDING.top + innerH}
                stroke="#0f0"
                strokeWidth={1}
              />
              <text
                x={WIDTH / 2}
                y={HEIGHT - 8}
                fill="#0f0"
                fontSize={11}
                textAnchor="middle"
                fontFamily="monospace"
              >
                {stock_name} share value per share
              </text>
            </svg>
          </Box>
        </Section>
      </Window.Content>
    </Window>
  );
};
