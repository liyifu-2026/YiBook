export interface BBox {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

export function findInkBBox(gray: Uint8Array, width: number, height: number,
  inkThreshold: number): BBox | null {
  let left = -1;
  let top = -1;
  let right = -1;
  let bottom = -1;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      if (gray[y * width + x] < inkThreshold) {
        if (left < 0 || x < left) {
          left = x;
        }
        if (top < 0) {
          top = y;
        }
        if (x > right) {
          right = x;
        }
        bottom = y;
      }
    }
  }
  if (left < 0) {
    return null;
  }
  const box: BBox = { left: left, top: top, right: right, bottom: bottom };
  return box;
}

export interface ParityCrop {
  even: BBox | null;
  odd: BBox | null;
}

function unionBox(a: BBox | null, b: BBox): BBox {
  if (a === null) {
    const only: BBox = { left: b.left, top: b.top, right: b.right, bottom: b.bottom };
    return only;
  }
  const box: BBox = {
    left: Math.min(a.left, b.left),
    top: Math.min(a.top, b.top),
    right: Math.max(a.right, b.right),
    bottom: Math.max(a.bottom, b.bottom)
  };
  return box;
}

export function clusterByParity(pageBoxes: Array<BBox | null>): ParityCrop {
  let even: BBox | null = null;
  let odd: BBox | null = null;
  for (let i = 0; i < pageBoxes.length; i++) {
    const b = pageBoxes[i];
    if (b === null) {
      continue;
    }
    if (i % 2 === 0) {
      even = unionBox(even, b);
    } else {
      odd = unionBox(odd, b);
    }
  }
  const crop: ParityCrop = { even: even, odd: odd };
  return crop;
}
