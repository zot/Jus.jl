all: jus.so samples

jus.so:
	julia -q -e 'using PackageCompiler, Pkg; Pkg.activate("."); using HTTP, JSON3, Match, Revise; create_sysimage(["HTTP", "JSON3", "Match", "Revise"]; sysimage_path="jus.so")'

samples: FRC
	cd samples; $(MAKE)

watch: FRC
	cd samples; $(MAKE) watch

FRC:
