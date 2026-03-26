import type { Config } from 'tailwindcss'

export default {
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        ocean: {
          deep: '#0B1426',
          midnight: '#0D2137',
          ink: '#1A3A5C',
          water: '#2389E8',
          sui: '#4DA2FF',
          teal: '#0EA5E9',
          sky: '#6FBCFF',
          foam: '#B8DEFF',
          mist: '#E8F4FF',
          surface: '#F7FBFF',
        },
      },
      fontFamily: {
        sans: ['Inter', '-apple-system', 'system-ui', 'sans-serif'],
        mono: ['SF Mono', 'Fira Code', 'monospace'],
      },
    },
  },
  plugins: [],
} satisfies Config
