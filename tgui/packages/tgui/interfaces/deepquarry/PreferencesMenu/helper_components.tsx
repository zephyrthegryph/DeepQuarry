// DQAdd — Helper components for canvas-backed sprite rendering, ported from the deleted
// bay_prefs/helper_components.tsx. Lets editors render colorized in-game icons over an
// off-screen canvas (e.g. marking sprites tinted by user color, with a human silhouette
// background for context). See BodyMarkingsEditor for a consumer.

import {
  type PropsWithChildren,
  type ReactNode,
  useCallback,
  useEffect,
  useRef,
  useState,
} from 'react';
import { Button, ColorBox, ImageButton, Stack } from 'tgui-core/components';

// In-memory cache of fetched HTMLImageElement promises, keyed by URL. Without
// this, every render of a thumbnail picker re-fires the network fetch — the
// hair/marking picker re-runs ColorizedImage on every poll. Sharing the promise
// also de-duplicates concurrent fetches for the same URL.
const imageCache = new Map<string, Promise<HTMLImageElement>>();

export const getImage = (url: string): Promise<HTMLImageElement> => {
  const cached = imageCache.get(url);
  if (cached) return cached;
  const promise = new Promise<HTMLImageElement>((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve(image);
    image.onerror = (event) => {
      imageCache.delete(url);
      reject(event);
    };
    image.src = url;
  });
  imageCache.set(url, promise);
  return promise;
};

/// Preload an image (e.g. on hover) so the click-to-open path renders instantly.
export const preloadImage = (url: string): void => {
  void getImage(url);
};

/// Cache of finished CanvasBackedImage data: URLs by render key. Lets the
/// picker re-mount without re-running the OffscreenCanvas pipeline for sprites
/// we've already drawn this session.
const bitmapCache = new Map<string, string>();

/// Runs at most `limit` tasks at once, the rest in arrival order: a picker's sprites must not all hit the client's
/// resource server and the canvas pipeline in the same frame.
export const makeLimiter = (limit: number) => {
  let running = 0;
  const waiting: Array<() => void> = [];
  return async <T,>(task: () => Promise<T>): Promise<T> => {
    if (running >= limit) {
      await new Promise<void>((resolve) => waiting.push(resolve));
    } else {
      running++;
    }
    try {
      return await task();
    } finally {
      const next = waiting.shift();
      if (next) next();
      else running--;
    }
  };
};
const renderLimit = makeLimiter(8);

/// Whether the element has come near the visible part of its scroller (once true, stays true).
const useNearView = <T extends Element>(enabled: boolean) => {
  const ref = useRef<T | null>(null);
  const [near, setNear] = useState(false);
  useEffect(() => {
    if (!enabled || near || !ref.current) return;
    if (typeof IntersectionObserver === 'undefined') {
      setNear(true);
      return;
    }
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) setNear(true);
      },
      { rootMargin: '200px' },
    );
    observer.observe(ref.current);
    return () => observer.disconnect();
  }, [enabled, near]);
  return [ref, near] as const;
};

/// Renders the output of a user-supplied OffscreenCanvas draw callback into an <img>.
/// Re-renders when the render prop reference changes; caller should memoize via useCallback.
/// Pass `cacheKey` to reuse the rendered data: URL across remounts (much cheaper
/// than re-running the canvas pipeline). Without `cacheKey`, every mount runs the
/// render afresh.
export const CanvasBackedImage = (props: {
  render: (
    canvas: OffscreenCanvas,
    ctx: OffscreenCanvasRenderingContext2D,
  ) => Promise<void>;
  size?: number;
  cacheKey?: string;
}) => {
  const cached = props.cacheKey ? bitmapCache.get(props.cacheKey) : undefined;
  const [bitmap, setBitmap] = useState<string>(cached ?? '');
  const size = props.size ?? 64;
  const [placeholder, near] = useNearView<HTMLSpanElement>(!bitmap);

  useEffect(() => {
    // Fast path: cached value already populated, no need to re-render.
    if (props.cacheKey && bitmapCache.has(props.cacheKey)) {
      setBitmap(bitmapCache.get(props.cacheKey) ?? '');
      return;
    }
    if (!near) return;
    const offscreenCanvas = new OffscreenCanvas(size, size);
    const ctx = offscreenCanvas.getContext('2d');
    if (!ctx) return;

    let active = true;
    let url = '';

    (async () => {
      // Queued long enough to have scrolled away or closed: skip the work.
      const blob = await renderLimit(async () => {
        if (!active) return null;
        await props.render(offscreenCanvas, ctx);
        return offscreenCanvas.convertToBlob();
      });
      if (!active || !blob) return;
      // Use FileReader to get a data: URL — survives unmount/remount where
      // ObjectURL would be revoked. Slightly larger but cacheable.
      const reader = new FileReader();
      reader.onload = () => {
        if (!active) return;
        url = reader.result as string;
        if (props.cacheKey) bitmapCache.set(props.cacheKey, url);
        setBitmap(url);
      };
      reader.readAsDataURL(blob);
    })();

    return () => {
      active = false;
    };
  }, [props.render, size, props.cacheKey, near]);

  // imageRendering: 'pixelated' — the OffscreenCanvas draws at 1 px = 1 source-px, but at
  // HiDPI scaling the <img> picks bilinear by default and DMI sprites end up blurry.
  return bitmap ? (
    <img
      src={bitmap}
      width={size}
      height={size}
      draggable={false}
      alt=""
      style={{ imageRendering: 'pixelated' }}
    />
  ) : (
    <span
      ref={placeholder}
      style={{ display: 'inline-block', width: size, height: size }}
    />
  );
};

/// Renders an icon_state from a DMI ref, tinted with `color`. The standard pattern is:
///   draw sprite → multiply by color → mask to original alpha.
export const ColorizedImage = (props: {
  iconRef: string;
  iconState: string;
  preRender?: (ctx: OffscreenCanvasRenderingContext2D) => Promise<void>;
  postRender?: (ctx: OffscreenCanvasRenderingContext2D) => Promise<void>;
  color?: string | null;
  dir?: string;
  size?: number;
}) => {
  const { iconRef, iconState, color, dir, preRender, postRender, size } = props;

  const render = useCallback(
    async (canvas: OffscreenCanvas, ctx: OffscreenCanvasRenderingContext2D) => {
      ctx.imageSmoothingEnabled = false;
      const px = canvas.width;

      if (preRender) await preRender(ctx);

      const finalDir = dir || '2';

      let image: HTMLImageElement;
      try {
        image = await getImage(
          `${iconRef}?state=${iconState}&dir=${finalDir}&frame=1`,
        );
      } catch {
        ctx.fillStyle = '#ff0000';
        ctx.fillRect(0, 0, px, px);
        return;
      }

      ctx.drawImage(image, 0, 0, px, px);

      // Multiply by color
      ctx.globalCompositeOperation = 'multiply';
      ctx.fillStyle = color || '#ffffff';
      ctx.fillRect(0, 0, px, px);

      // Mask back to original alpha
      ctx.globalCompositeOperation = 'destination-in';
      ctx.drawImage(image, 0, 0, px, px);

      if (postRender) {
        ctx.globalCompositeOperation = 'source-over';
        await postRender(ctx);
      }
    },
    [iconRef, iconState, color, preRender, postRender, dir],
  );

  // Stable cache key so repeated renders + remounts (e.g. switching tabs back
  // to the hair picker) reuse the previously-drawn data URL.
  const cacheKey = `${iconRef}|${iconState}|${color ?? ''}|${dir ?? ''}|${size ?? 64}`;
  return <CanvasBackedImage render={render} size={size} cacheKey={cacheKey} />;
};

const GRADIENT_THUMB_HAIR = '#5a4a42';
const GRADIENT_THUMB_TINT = '#ff9a2e';

/// A hair gradient on a hair sprite, composed the way the game does: the hair, then the gradient cut to the hair's shape.
export const HairGradientImage = (props: {
  hairRef: string;
  hairState: string;
  gradientRef: string;
  gradientState: string;
  size?: number;
}) => {
  const { hairRef, hairState, gradientRef, gradientState, size } = props;
  const render = useCallback(
    async (canvas: OffscreenCanvas, ctx: OffscreenCanvasRenderingContext2D) => {
      ctx.imageSmoothingEnabled = false;
      const px = canvas.width;
      const hair = await getImage(
        `${hairRef}?state=${hairState}&dir=2&frame=1`,
      );
      const gradient = await getImage(
        `${gradientRef}?state=${gradientState}&dir=2&frame=1`,
      );
      ctx.drawImage(hair, 0, 0, px, px);
      ctx.globalCompositeOperation = 'source-in';
      ctx.fillStyle = GRADIENT_THUMB_HAIR;
      ctx.fillRect(0, 0, px, px);
      const layer = new OffscreenCanvas(px, px);
      const layerCtx = layer.getContext('2d');
      if (!layerCtx) return;
      layerCtx.imageSmoothingEnabled = false;
      layerCtx.drawImage(gradient, 0, 0, px, px);
      layerCtx.globalCompositeOperation = 'source-in';
      layerCtx.fillStyle = GRADIENT_THUMB_TINT;
      layerCtx.fillRect(0, 0, px, px);
      layerCtx.globalCompositeOperation = 'destination-in';
      layerCtx.drawImage(hair, 0, 0, px, px);
      ctx.globalCompositeOperation = 'source-over';
      ctx.drawImage(layer, 0, 0);
    },
    [hairRef, hairState, gradientRef, gradientState],
  );
  return (
    <CanvasBackedImage
      render={render}
      size={size}
      cacheKey={`gradient|${hairRef}|${hairState}|${gradientState}|${size ?? 64}`}
    />
  );
};

/// One sprite of a LayeredImage, bottom first.
export type ImageLayer = {
  icon: string;
  icon_state: string;
  color?: string | null;
  blend?: 'multiply' | 'add';
};

/// Where each sprite of a LayeredImage lands on a `px` square: every sprite shares one scale, set by the smallest
/// sprite (the body's 32-pixel tile) filling the square, centred horizontally and standing on the bottom edge, as
/// BYOND draws an oversized sprite over its tile. A 64-pixel wing or taur overhangs the square and is clipped; the
/// body is never shrunk to make room for it.
export const layerPlacements = (
  px: number,
  sizes: ({ width: number; height: number } | null)[],
) => {
  const loaded = sizes.filter((s): s is { width: number; height: number } => !!s);
  const tile = Math.max(
    1,
    loaded.length ? Math.min(...loaded.map((s) => Math.max(s.width, s.height))) : 1,
  );
  const unit = px / tile;
  return sizes.map((s) => {
    if (!s) return null;
    const w = s.width * unit;
    const h = s.height * unit;
    return { x: (px - w) / 2, y: px - h, w, h };
  });
};

/// Sprites stacked into one picture, each tinted on its own: a body with a part on it, placed by layerPlacements.
/// A sprite that fails to load is left out.
export const LayeredImage = (props: {
  layers: ImageLayer[];
  size?: number;
}) => {
  const { layers, size } = props;
  const key = layers
    .map((l) => `${l.icon}|${l.icon_state}|${l.color ?? ''}|${l.blend ?? ''}`)
    .join(';');
  const render = useCallback(
    async (canvas: OffscreenCanvas, ctx: OffscreenCanvasRenderingContext2D) => {
      ctx.imageSmoothingEnabled = false;
      const px = canvas.width;
      const images = await Promise.all(
        layers.map((l) =>
          getImage(`${l.icon}?state=${l.icon_state}&dir=2&frame=1`).catch(
            () => null,
          ),
        ),
      );
      const placements = layerPlacements(px, images);
      images.forEach((image, index) => {
        const place = placements[index];
        if (!image || !place) return;
        const { x, y, w, h } = place;
        const layer = new OffscreenCanvas(px, px);
        const lctx = layer.getContext('2d');
        if (!lctx) return;
        lctx.imageSmoothingEnabled = false;
        lctx.drawImage(image, x, y, w, h);
        const color = layers[index].color;
        if (color) {
          lctx.globalCompositeOperation =
            layers[index].blend === 'add' ? 'lighter' : 'multiply';
          lctx.fillStyle = color;
          lctx.fillRect(0, 0, px, px);
          lctx.globalCompositeOperation = 'destination-in';
          lctx.drawImage(image, x, y, w, h);
        }
        ctx.drawImage(layer, 0, 0);
      });
    },
    [layers],
  );
  return (
    <CanvasBackedImage
      render={render}
      size={size}
      cacheKey={`layers|${key}|${size ?? 64}`}
    />
  );
};

/// ImageButton wrapper that takes an arbitrary ReactNode as the image. Useful with
/// ColorizedImage above when the image is computed on the fly.
export const CustomImageButton = (
  props: PropsWithChildren<{
    image: ReactNode;
    tooltip?: string;
    selected?: boolean;
    onClick: () => void;
    buttons?: ReactNode;
  }>,
) => (
  <ImageButton
    dmIcon="not_a_real_icon.dmi"
    dmIconState="equally_fake_icon_state"
    dmFallback={props.image}
    onClick={props.onClick}
    tooltip={props.tooltip}
    selected={props.selected}
    buttons={props.buttons}
    verticalAlign="top"
  >
    {props.children}
  </ImageButton>
);

export const ColorizedImageButton = (
  props: PropsWithChildren<{
    iconRef: string;
    iconState: string;
    color?: string | null;
    dir?: string;
    onClick: () => void;
    preRender?: (ctx: OffscreenCanvasRenderingContext2D) => Promise<void>;
    postRender?: (ctx: OffscreenCanvasRenderingContext2D) => Promise<void>;
    selected?: boolean;
    tooltip?: string;
    buttons?: ReactNode;
  }>,
) => {
  const {
    iconRef,
    iconState,
    color,
    dir,
    onClick,
    selected,
    preRender,
    postRender,
  } = props;

  return (
    <CustomImageButton
      image={
        <ColorizedImage
          iconRef={iconRef}
          iconState={iconState}
          color={color}
          dir={dir}
          preRender={preRender}
          postRender={postRender}
        />
      }
      onClick={onClick}
      selected={selected}
      tooltip={props.tooltip}
      buttons={props.buttons}
    >
      {props.children}
    </CustomImageButton>
  );
};

export enum ColorType {
  First,
  Second,
  Third,
  Alpha,
}

export const ColorPicker = (props: {
  onClick: (type: ColorType) => void;
  color_one?: string | null;
  color_two?: string | null;
  color_three?: string | null;
  alpha?: number;
}) => {
  const { onClick, color_one, color_two, color_three, alpha } = props;
  return (
    <Stack>
      <Stack.Item>
        <Button onClick={() => onClick(ColorType.First)}>
          First Color: <ColorBox color={color_one} />
        </Button>
      </Stack.Item>
      {!!color_two && (
        <Stack.Item>
          <Button onClick={() => onClick(ColorType.Second)}>
            Second Color: <ColorBox color={color_two} />
          </Button>
        </Stack.Item>
      )}
      {!!color_three && (
        <Stack.Item>
          <Button onClick={() => onClick(ColorType.Third)}>
            Third Color: <ColorBox color={color_three} />
          </Button>
        </Stack.Item>
      )}
      {alpha !== undefined && (
        <Stack.Item>
          <Button onClick={() => onClick(ColorType.Alpha)}>
            Alpha: {alpha}
          </Button>
        </Stack.Item>
      )}
    </Stack>
  );
};
