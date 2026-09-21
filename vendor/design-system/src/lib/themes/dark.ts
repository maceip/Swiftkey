const darkTheme = {
  '.maximeheckel-dark': {
    '--base-hue': '320',
    '--white': 'oklch(100% 0 0)',

    /* TypeSafe Dark Neutrals: #1E1E1E dark background, #252525 card, #2E2E2E border, #FEFEFE text primary */
    '--gray-000': 'oklch(15.0% 0.005 var(--base-hue))', /* #121212 */
    '--gray-100': 'oklch(18.0% 0.005 var(--base-hue))', /* #181818 */
    '--gray-200': 'oklch(23.50% 0 0)', /* #1E1E1E TypeSafe dark background */
    '--gray-300': 'oklch(26.0% 0.005 var(--base-hue))', /* #252525 TypeSafe dark card background */
    '--gray-400': 'oklch(30.0% 0.006 var(--base-hue))', /* #2E2E2E TypeSafe dark border */
    '--gray-500': 'oklch(35.0% 0.008 var(--base-hue))', /* #383838 */
    '--gray-600': 'oklch(43.0% 0.010 var(--base-hue))', /* #4D4A50 */
    '--gray-700': 'oklch(52.78% 0 0)', /* #6B6B6B TypeSafe secondary text dark */
    '--gray-800': 'oklch(65.0% 0.012 var(--base-hue))', /* #98949B */
    '--gray-900': 'oklch(77.70% 0.0167 192)', /* #ABBAB9 TypeSafe sage-slate */
    '--gray-1000': 'oklch(84.0% 0.008 192)', /* #D0D5D4 */
    '--gray-1100': 'oklch(92.19% 0 0)', /* #E5E5E5 */
    '--gray-1200': 'oklch(99.0% 0 0)', /* #FEFEFE TypeSafe white text */

    /* TypeSafe Blue Palette (#3B7AD3 cube blue, hue 257.5) */
    '--blue-100': 'oklch(22.0% 0.040 257.5)',
    '--blue-200': 'oklch(26.0% 0.060 257.5)',
    '--blue-300': 'oklch(32.0% 0.080 257.5)',
    '--blue-400': 'oklch(40.0% 0.110 257.5)',
    '--blue-500': 'oklch(49.0% 0.140 257.5)',
    '--blue-600': 'oklch(58.31% 0.1514 257.5)', /* #3B7AD3 */
    '--blue-700': 'oklch(68.0% 0.140 257.5)',
    '--blue-800': 'oklch(76.0% 0.120 257.5)',
    '--blue-900': 'oklch(84.0% 0.090 257.5)',
    '--blue-1000': 'oklch(90.0% 0.060 257.5)',
    '--blue-1100': 'oklch(94.5% 0.035 257.5)',
    '--blue-1200': 'oklch(98.0% 0.015 257.5)',

    /* TypeSafe Green Palette (#03AA5C benchmark green, hue 153.4) */
    '--green-100': 'oklch(22.0% 0.040 153.4)',
    '--green-200': 'oklch(26.0% 0.060 153.4)',
    '--green-300': 'oklch(32.0% 0.080 153.4)',
    '--green-400': 'oklch(40.0% 0.110 153.4)',
    '--green-500': 'oklch(50.0% 0.140 153.4)',
    '--green-600': 'oklch(58.0% 0.160 153.4)',
    '--green-700': 'oklch(64.75% 0.1647 153.4)', /* #03AA5C */
    '--green-800': 'oklch(74.0% 0.150 153.4)',
    '--green-900': 'oklch(84.0% 0.130 153.4)',
    '--green-1000': 'oklch(89.0% 0.100 153.4)',
    '--green-1100': 'oklch(93.5% 0.060 153.4)',
    '--green-1200': 'oklch(97.5% 0.025 153.4)',

    /* TypeSafe Red / Terracotta Palette (#8F4A31 terracotta, hue 40.3 / #E05D44, hue 28) */
    '--red-100': 'oklch(20.0% 0.050 28)',
    '--red-200': 'oklch(24.0% 0.070 28)',
    '--red-300': 'oklch(30.0% 0.090 28)',
    '--red-400': 'oklch(37.0% 0.120 28)',
    '--red-500': 'oklch(48.87% 0.1007 40.3)', /* #8F4A31 TypeSafe terracotta */
    '--red-600': 'oklch(56.0% 0.160 28)',
    '--red-700': 'oklch(64.0% 0.180 28)',
    '--red-800': 'oklch(72.0% 0.160 28)',
    '--red-900': 'oklch(80.0% 0.130 28)',
    '--red-1000': 'oklch(86.0% 0.090 28)',
    '--red-1100': 'oklch(92.0% 0.055 28)',
    '--red-1200': 'oklch(96.5% 0.025 28)',

    /* TypeSafe Amber / Gold Palette (#C18724 cube gold, hue 75.3) */
    '--orange-100': 'oklch(22.0% 0.040 75.3)',
    '--orange-200': 'oklch(26.0% 0.055 75.3)',
    '--orange-300': 'oklch(32.0% 0.075 75.3)',
    '--orange-400': 'oklch(40.0% 0.095 75.3)',
    '--orange-500': 'oklch(50.0% 0.115 75.3)',
    '--orange-600': 'oklch(60.0% 0.125 75.3)',
    '--orange-700': 'oklch(66.54% 0.1285 75.3)', /* #C18724 */
    '--orange-800': 'oklch(75.0% 0.125 75.3)',
    '--orange-900': 'oklch(82.0% 0.110 75.3)',
    '--orange-1000': 'oklch(88.0% 0.080 75.3)',
    '--orange-1100': 'oklch(93.0% 0.050 75.3)',
    '--orange-1200': 'oklch(97.0% 0.020 75.3)',

    /* Unique Warm Purple Palette — captures the warmth of #F386A1 at hue 320 */
    '--purple-100': 'oklch(22.0% 0.050 320)',
    '--purple-200': 'oklch(26.0% 0.070 320)',
    '--purple-300': 'oklch(32.0% 0.090 320)',
    '--purple-400': 'oklch(40.0% 0.120 320)',
    '--purple-500': 'oklch(50.0% 0.160 320)',
    '--purple-600': 'oklch(60.0% 0.190 320)',
    '--purple-700': 'oklch(68.0% 0.180 320)',
    '--purple-800': 'oklch(74.59% 0.1353 320)', /* #D28FE2: glowing warm purple accent in dark mode */
    '--purple-900': 'oklch(82.0% 0.110 320)',
    '--purple-1000': 'oklch(88.0% 0.080 320)',
    '--purple-1100': 'oklch(93.0% 0.050 320)',
    '--purple-1200': 'oklch(97.0% 0.020 320)',

    /* Legacy pink tokens aliased to warm purple */
    '--pink-100': 'var(--purple-100)',
    '--pink-200': 'var(--purple-200)',
    '--pink-300': 'var(--purple-300)',
    '--pink-400': 'var(--purple-400)',
    '--pink-500': 'var(--purple-500)',
    '--pink-600': 'var(--purple-600)',
    '--pink-700': 'var(--purple-700)',
    '--pink-800': 'var(--purple-800)',
    '--pink-900': 'var(--purple-900)',
    '--pink-1000': 'var(--purple-1000)',
    '--pink-1100': 'var(--purple-1100)',
    '--pink-1200': 'var(--purple-1200)',

    /* Semantic Tokens */
    '--accent': 'var(--purple-800)',
    '--background': 'var(--gray-200)',
    '--header': 'oklch(from var(--gray-200) l c h / 60%)',
    '--emphasis': 'oklch(from var(--purple-800) l c h / 12%)',
    '--hyperlink': 'var(--purple-700)',

    '--foreground': 'var(--gray-1200)',
    '--danger': 'var(--red-800)',
    '--danger-emphasis': 'oklch(from var(--red-800) l c h / 15%)',
    '--warning': 'var(--orange-800)',
    '--warning-emphasis': 'oklch(from var(--orange-800) l c h / 15%)',
    '--success': 'var(--green-800)',
    '--success-emphasis': 'oklch(from var(--green-800) l c h / 15%)',

    '--text-primary': 'var(--gray-1200)',
    '--text-secondary': 'var(--gray-900)',
    '--text-tertiary': 'var(--gray-700)',
    '--border-color': 'var(--gray-400)',
    '--card-background': 'var(--gray-300)',
    '--input-active': 'var(--accent)',
    '--input-background': 'var(--gray-100)',
    '--input-disabled': 'var(--gray-400)',
    '--input-border': 'var(--gray-500)',
    '--input-focus': 'var(--purple-600)',
    '--shadow-color': 'var(--local-shadow-color, 320deg 15% 5%)',
    '--code-snippet-background': 'var(--gray-300)',
    '--token-comment': 'var(--gray-700)',
    '--token-selector': 'var(--accent)',
    '--token-symbol': 'var(--purple-700)',
    '--token-operator': 'var(--orange-800)',
    '--token-keyword': 'var(--blue-700)',
    '--token-function': 'var(--purple-800)',
    '--token-punctuation': 'var(--purple-700)',

    '@supports not (color: rgb(from white r g b))': {
      '--header': 'oklch(23.50% 0 0 / 60%)',
      '--emphasis': 'oklch(74.59% 0.1353 var(--base-hue) / 12%)',

      '--danger-emphasis': 'oklch(72.0% 0.160 28 / 15%)',
      '--warning-emphasis': 'oklch(75.0% 0.125 75.3 / 15%)',
      '--success-emphasis': 'oklch(74.0% 0.150 153.4 / 15%)',
    },
  },
};

export default darkTheme;
