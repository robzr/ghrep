GHLIB=lib/ghrep

all : ghrep

ghrep : bin/ghrep

bin/ghrep : $(GHLIB).rb $(GHLIB)/*.rb
	sed -n "s/^require_relative '\(.*\)'/\1/p" ghrep | while read lib ; do \
	  echo Embedding $${lib}... ; \
	  sed -e "s|^require_relative '$$lib'|#&|" -e "\|^#require_relative '$$lib'|r $$lib" ghrep > bin/ghrep ; \
	done 
	sed -n "s/^require_relative '\(.*\)'/\1/p" bin/ghrep | while read lib ; do \
	  echo Embedding $${lib}... ; \
	  sed -e "s|^require_relative '$$lib'|#&|" -e "\|^#require_relative '$$lib'|r lib/$$lib" -i '' bin/ghrep ; \
	done
	chmod 755 bin/ghrep

clean : ; rm -f bin/ghrep

