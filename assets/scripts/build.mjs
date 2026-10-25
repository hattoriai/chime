// The bundles of Chime's JavaScript, in priv/static: the client, and its
// React hooks and components (React left to the app), and their types.
import { execFileSync } from "node:child_process";
import { build } from "esbuild";

const common = { bundle: true, format: "esm", target: "es2020", minify: false, legalComments: "none" };

await build({ ...common, entryPoints: ["src/index.ts"], outfile: "../priv/static/chime.js" });

// The React bundle imports the client's, so an app has one of each.
const client = {
  name: "client",
  setup(build) {
    build.onResolve({ filter: /^\.\/index$/ }, () => ({ path: "./chime.js", external: true }));
  },
};

await build({
  ...common,
  entryPoints: ["src/react.tsx"],
  outfile: "../priv/static/chime-react.js",
  external: ["react", "react/jsx-runtime"],
  jsx: "automatic",
  plugins: [client],
});

execFileSync("npx", ["tsc", "-p", "tsconfig.build.json"], { stdio: "inherit" });
