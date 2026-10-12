import commonjs from "@rollup/plugin-commonjs";
import nodeResolve from "@rollup/plugin-node-resolve";
import typescript from "@rollup/plugin-typescript";
import path from "node:path";
import url from "node:url";

const sdPlugin = "com.mlapin.marstek.sdPlugin";

export default {
	input: "src/plugin.ts",
	output: {
		file: `${sdPlugin}/bin/plugin.js`,
		format: "es",
		sourcemap: true,
		sourcemapPathTransform: (relativeSourcePath, sourcemapPath) =>
			url.pathToFileURL(path.resolve(path.dirname(sourcemapPath), relativeSourcePath)).href,
	},
	plugins: [
		{
			name: "watch-externals",
			buildStart() {
				this.addWatchFile(`${sdPlugin}/manifest.json`);
			},
		},
		typescript({ mapRoot: null }),
		nodeResolve({ browser: false, exportConditions: ["node"], preferBuiltins: true }),
		commonjs(),
	],
};
