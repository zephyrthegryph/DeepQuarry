// DQAdd — Helper components for canvas-backed sprite rendering, ported from the deleted
// bay_prefs/helper_components.tsx. Lets editors render colorized in-game icons over an
// off-screen canvas (e.g. marking sprites tinted by user color, with a human silhouette
// background for context). See BodyMarkingsEditor for a consumer.

import {
  type PropsWithChildren,
  type ReactNode,
  useCallback,
  useEffect,
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

  useEffect(() => {
    // Fast path: cached value already populated, no need to re-render.
    if (props.cacheKey && bitmapCache.has(props.cacheKey)) {
      setBitmap(bitmapCache.get(props.cacheKey) ?? '');
      return;
    }
    const offscreenCanvas = new OffscreenCanvas(size, size);
    const ctx = offscreenCanvas.getContext('2d');
    if (!ctx) return;

    let active = true;
    let url = '';

    (async () => {
      await props.render(offscreenCanvas, ctx);
      const blob = await offscreenCanvas.convertToBlob();
      if (!active) return;
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
  }, [props.render, size, props.cacheKey]);

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
  ) : null;
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
