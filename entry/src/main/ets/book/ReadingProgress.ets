export function updateHighWater(prevHighWaterPage: number, currentPage: number): number {
  return currentPage > prevHighWaterPage ? currentPage : prevHighWaterPage;
}
