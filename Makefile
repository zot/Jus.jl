all: jus.so samples

jus.so:
	julia -q -e 'using PackageCompiler, Pkg; Pkg.activate("."); using HTTP, JSON3, Match, Revise; create_sysimage(["HTTP", "JSON3", "Match", "Revise"]; sysimage_path="jus.so")'

samples: FRC
	cd samples; $(MAKE)

run: FRC
	./jus ROOT -s localhost:7777

watch: FRC
	cd samples; $(MAKE) watch

FRC:
