import type { Config } from 'tailwindcss';
import tailwindcssAnimate from 'tailwindcss-animate';

const config: Config = {
  darkMode: ['class', 'media'],
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      fontFamily: {
        sans: ['"DM Sans"', 'Inter', 'system-ui', '-apple-system', 'sans-serif'],
        mono: ['"DM Mono"', '"JetBrains Mono"', '"Fira Code"', '"SF Mono"', 'monospace'],
      },
    },
  },
  plugins: [tailwindcssAnimate],
};

export default config;
