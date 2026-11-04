import base from '/Users/jamaki604/CleanStreamProjects/CleanStreamWeb-CortinaQR/vite.config.js';

export default {
  ...base,
  test: { ...base.test, setupFiles: new URL('./qa.setup.mjs', import.meta.url).pathname },
  cacheDir: new URL('./.qa-cache/vite/', import.meta.url).pathname,
};
