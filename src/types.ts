export type Point = [number, number]

/** Points are normalized 0..1 against the image's natural size, so strokes
 *  survive window resizing and export at full resolution. */
export type Stroke = { points: Point[] }

export type Shot = {
  id: string
  name: string
  src: string
  width: number
  height: number
  strokes: Stroke[]
  note: string
}
