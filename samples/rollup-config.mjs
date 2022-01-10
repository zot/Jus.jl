import { nodeResolve } from '@rollup/plugin-node-resolve';

export default {
  input: 'people.mjs',
  output: {
    dir: 'output',
    format: 'es'
  },
  watch: {
    include: [
      "jus.mjs",
      "people.mjs",
      "vars.mjs",
      "views.mjs"
    ]
  },
  plugins: [nodeResolve()]
};
