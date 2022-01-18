all: jus.so samples

jus.so:
	julia -q -e 'using PackageCompiler, Pkg; Pkg.activate("."); using HTTP, JSON3, Match, Revise; create_sysimage(["HTTP", "JSON3", "Match", "Revise"]; sysimage_path="jus.so")'

samples: samples/output/widgets.js

run: FRC
	./jus ROOT -s localhost:7777

samples/output/people.js:
	rollup -c rollup-widgets.mjs

watch: FRC
	rollup -c rollup-widgets.mjs -w

FRC:
