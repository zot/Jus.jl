jus.so:
	julia -q -e 'using PackageCompiler, Pkg; Pkg.activate("."); using HTTP, JSON3, Match, Revise; create_sysimage(["HTTP", "JSON3", "Match", "Revise"]; sysimage_path="jus.so")'
