export const PASTED_ORIGINAL_SONG_DELIMITER_PATTERN = /[,、，\/／]/

export function shouldDistributePastedRows(rows, shiftKeyDown) {
  return Boolean(shiftKeyDown) || rows.some((row) => PASTED_ORIGINAL_SONG_DELIMITER_PATTERN.test(row))
}
