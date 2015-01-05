all:
	pandoc                                              \
		-t html5                                        \
		--template=templates/template-revealjs.html     \
		--standalone                                    \
		--section-divs                                  \
		--variable theme="default"                      \
		--variable transition="default"                 \
		-s r10k_demo.md                                 \
		-o index.html

