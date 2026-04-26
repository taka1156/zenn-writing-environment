/**
 * @type {import('lint-staged').Configuration}
 */
export default {
  '**/*.{md}': ['textlint ./articles/**/*.md'],
};
