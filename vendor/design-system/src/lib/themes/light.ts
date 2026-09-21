const lightTheme = {
  '.maximeheckel-light': {
    '--base-hue': '320',
    '--white': 'oklch(100% 0 0)',

    /* TypeSafe Neutrals: Crisp white, #E5E5E5 / #DEDEDE borders, #6B6B6B text secondary, #1E1E1E text primary */
    '--gray-000': 'oklch(100% 0 0)',
    '--gray-100': 'oklch(99.2% 0.003 var(--base-hue))',
    '--gray-200': 'oklch(98.0% 0.004 var(--base-hue))',
    '--gray-300': 'oklch(95.5% 0.005 var(--base-hue))',
    '--gray-400': 'oklch(92.19% 0 0)', /* #E5E5E5 TypeSafe border */
    '--gray-500': 'oklch(90.06% 0 0)', /* #DEDEDE TypeSafe line */
    '--gray-600': 'oklch(84.0% 0.008 192)',
    '--gray-700': 'oklch(77.70% 0.0167 192)', /* #ABBAB9 TypeSafe sage-slate */
    '--gray-800': 'oklch(66.0% 0.010 var(--base-hue))',
    '--gray-900': 'oklch(52.78% 0 0)', /* #6B6B6B TypeSafe secondary text */
    '--gray-1000': 'oklch(40.0% 0.008 var(--base-hue))',
    '--gray-1100': 'oklch(30.0% 0.006 var(--base-hue))',
    '--gray-1200': 'oklch(23.50% 0 0)', /* #1E1E1E TypeSafe primary text */

    /* TypeSafe Blue Palette (#3B7AD3 cube blue, hue 257.5) */
    '--blue-100': 'oklch(99.0% 0.012 257.5)',
    '--blue-200': 'oklch(97.5% 0.024 257.5)',
    '--blue-300': 'oklch(94.5% 0.045 257.5)',
    '--blue-400': 'oklch(90.0% 0.070 257.5)',
    '--blue-500': 'oklch(83.0% 0.095 257.5)',
    '--blue-600': 'oklch(76.0% 0.120 257.5)',
    '--blue-700': 'oklch(69.0% 0.140 257.5)',
    '--blue-800': 'oklch(63.0% 0.150 257.5)',
    '--blue-900': 'oklch(58.31% 0.1514 257.5)', /* #3B7AD3 */
    '--blue-1000': 'oklch(49.0% 0.155 257.5)',
    '--blue-1100': 'oklch(38.0% 0.135 257.5)',
    '--blue-1200': 'oklch(25.0% 0.090 257.5)',

    /* TypeSafe Green Palette (#03AA5C benchmark green, hue 153.4) */
    '--green-100': 'oklch(99.0% 0.015 153.4)',
    '--green-200': 'oklch(97.5% 0.030 153.4)',
    '--green-300': 'oklch(95.0% 0.050 153.4)',
    '--green-400': 'oklch(91.0% 0.080 153.4)',
    '--green-500': 'oklch(85.0% 0.110 153.4)',
    '--green-600': 'oklch(79.0% 0.135 153.4)',
    '--green-700': 'oklch(74.0% 0.150 153.4)',
    '--green-800': 'oklch(69.0% 0.160 153.4)',
    '--green-900': 'oklch(64.75% 0.1647 153.4)', /* #03AA5C */
    '--green-1000': 'oklch(56.0% 0.155 153.4)',
    '--green-1100': 'oklch(45.0% 0.130 153.4)',
    '--green-1200': 'oklch(26.0% 0.080 153.4)',

    /* TypeSafe Red / Terracotta Palette (#8F4A31 terracotta, hue 40.3 / #D33E3E, hue 28) */
    '--red-100': 'oklch(98.5% 0.010 28)',
    '--red-200': 'oklch(96.5% 0.025 28)',
    '--red-300': 'oklch(93.5% 0.045 28)',
    '--red-400': 'oklch(89.0% 0.075 28)',
    '--red-500': 'oklch(83.0% 0.110 28)',
    '--red-600': 'oklch(76.0% 0.145 28)',
    '--red-700': 'oklch(69.0% 0.175 28)',
    '--red-800': 'oklch(63.0% 0.190 28)',
    '--red-900': 'oklch(58.0% 0.190 28)', /* #D33E3E */
    '--red-1000': 'oklch(48.87% 0.1007 40.3)', /* #8F4A31 TypeSafe terracotta */
    '--red-1100': 'oklch(38.0% 0.090 40.3)',
    '--red-1200': 'oklch(24.0% 0.060 40.3)',

    /* TypeSafe Amber / Gold Palette (#C18724 cube gold, hue 75.3) */
    '--orange-100': 'oklch(98.5% 0.015 75.3)',
    '--orange-200': 'oklch(96.5% 0.030 75.3)',
    '--orange-300': 'oklch(93.5% 0.055 75.3)',
    '--orange-400': 'oklch(89.0% 0.080 75.3)',
    '--orange-500': 'oklch(84.0% 0.105 75.3)',
    '--orange-600': 'oklch(79.0% 0.120 75.3)',
    '--orange-700': 'oklch(74.0% 0.125 75.3)',
    '--orange-800': 'oklch(70.0% 0.128 75.3)',
    '--orange-900': 'oklch(66.54% 0.1285 75.3)', /* #C18724 */
    '--orange-1000': 'oklch(58.0% 0.130 75.3)',
    '--orange-1100': 'oklch(46.0% 0.110 75.3)',
    '--orange-1200': 'oklch(30.0% 0.075 75.3)',

    /* Unique Warm Purple Palette — captures the warmth of #F386A1 at hue 320 */
    '--purple-100': 'oklch(98.5% 0.015 320)',
    '--purple-200': 'oklch(96.5% 0.030 320)',
    '--purple-300': 'oklch(93.5% 0.050 320)',
    '--purple-400': 'oklch(88.0% 0.080 320)',
    '--purple-500': 'oklch(82.0% 0.110 320)',
    '--purple-600': 'oklch(74.59% 0.1353 320)', /* #D28FE2: exact warm purple equivalent of #F386A1 */
    '--purple-700': 'oklch(68.0% 0.170 320)',
    '--purple-800': 'oklch(60.0% 0.200 320)',
    '--purple-900': 'oklch(53.0% 0.220 320)', /* Rich warm purple for buttons & active states on light */
    '--purple-1000': 'oklch(44.0% 0.210 320)',
    '--purple-1100': 'oklch(35.0% 0.160 320)',
    '--purple-1200': 'oklch(24.0% 0.100 320)',

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
    '--accent': 'var(--purple-900)',
    '--background': 'var(--gray-000)',
    '--header': 'oklch(from var(--gray-000) l c h / 60%)',
    '--emphasis': 'oklch(from var(--purple-900) l c h / 7%)',
    '--hyperlink': 'var(--blue-900)',

    '--foreground': 'var(--gray-1200)',
    '--danger': 'var(--red-900)',
    '--danger-emphasis': 'oklch(from var(--red-900) l c h / 10%)',
    '--warning': 'var(--orange-900)',
    '--warning-emphasis': 'oklch(from var(--orange-900) l c h / 10%)',
    '--success': 'var(--green-900)',
    '--success-emphasis': 'oklch(from var(--green-900) l c h / 10%)',
    '--text-primary': 'var(--gray-1200)',
    '--text-secondary': 'var(--gray-900)',
    '--text-tertiary': 'var(--gray-700)',
    '--border-color': 'var(--gray-400)',
    '--card-background': 'var(--white)',
    '--input-active': 'var(--accent)',
    '--input-background': 'var(--gray-000)',
    '--input-disabled': 'var(--gray-300)',
    '--input-border': 'var(--gray-500)',
    '--input-focus': 'var(--purple-700)',
    '--shadow-color': 'var(--local-shadow-color, 320deg 10% 80%)',
    '--code-snippet-background': 'var(--gray-100)',
    '--token-comment': 'var(--gray-900)',
    '--token-selector': 'var(--accent)',
    '--token-symbol': 'var(--purple-1100)',
    '--token-operator': 'var(--gray-900)',
    '--token-keyword': 'var(--blue-900)',
    '--token-function': 'var(--purple-900)',
    '--token-punctuation': 'var(--purple-900)',

    '@supports not (color: rgb(from white r g b))': {
      '--header': 'oklch(100% 0 0 / 60%)',
      '--emphasis': 'oklch(53.0% 0.220 var(--base-hue) / 7%)',
      '--foreground': 'oklch(23.50% 0 0 / 100%)',

      '--danger-emphasis': 'oklch(58.0% 0.190 28 / 10%)',
      '--warning-emphasis': 'oklch(66.54% 0.1285 75.3 / 10%)',
      '--success-emphasis': 'oklch(64.75% 0.1647 153.4 / 10%)',
    },
  },
};

export default lightTheme;
