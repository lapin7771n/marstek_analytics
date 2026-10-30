// UI strings are the app's own, from ios/Shared/Localizable.xcstrings (uk). Captions are written for the reel.
export const NBSP = " ";

export const APP = {
  eta: "ДО РОЗРЯДУ",
  lasts: "ВИСТАЧИТЬ",
  lastsLine: `Вистачить до 18:00, запас 1${NBSP}год 20${NBSP}хв`,
  runsOutLine: `Сяде о 16:40, бракує 40${NBSP}хв`,
  cut: "Вимкніть потужні прилади",
  kyiv: "YASNO · лише Київ",
  hero: ["3", "год", "30", "хв"],
  heroText: `3${NBSP}год 30${NBSP}хв`,
  percent: `58${NBSP}%`,
} as const;

export const CAPTION = {
  hook: ["Чи вистачить батареї", "Marstek до кінця", "відключення?"],
  problem: ["Застосунок Marstek", "не показує, скільки", "часу лишилося"],
  answer: ["Battery ETA", "показує"],
  verdict: ["Вкажіть, коли", "дадуть світло"],
  tension: ["А якщо", "не вистачить?"],
  action: ["Попередить до", "відключення"],
} as const;

export const CTA = {
  name: "Battery ETA",
  action: "Шукайте в App Store",
  compat: "для Marstek Venus E 3.0",
} as const;
