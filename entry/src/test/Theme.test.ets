import { describe, it, expect } from '@ohos/hypium';
import { NIGHT, DAY, paletteOf } from '../main/ets/core/Theme';

export default function themeTest() {
  describe('theme', () => {
    it('day and night palettes share the same field contract', 0, () => {
      const nk = Object.keys(NIGHT).sort();
      const dk = Object.keys(DAY).sort();
      expect(JSON.stringify(nk)).assertEqual(JSON.stringify(dk));
    });

    it('accent and hard shadow discipline hold in both modes', 0, () => {
      expect(NIGHT.accent).assertEqual('#FF8A2A');
      expect(DAY.accent).assertEqual('#FF8A2A');
      expect(NIGHT.shadow).assertEqual('#060B12');
      expect(DAY.shadow).assertEqual('#060B12');
      expect(NIGHT.onAccent).assertEqual(DAY.onAccent);
    });

    it('paletteOf picks by flag', 0, () => {
      expect(paletteOf(true) === NIGHT).assertEqual(true);
      expect(paletteOf(false) === DAY).assertEqual(true);
    });
  });
}
