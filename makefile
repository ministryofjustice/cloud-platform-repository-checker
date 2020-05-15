VERSION := 1.0.4

cloud-platform-repository-checker.gemspec: Rakefile.template bin/* lib/*
	(export VERSION=$(VERSION); cat Rakefile.template | envsubst > Rakefile)
	rake package

publish: cloud-platform-repository-checker.gemspec
	gem push pkg/cloud-platform-repository-checker-$(VERSION).gem

clean:
	rm -rf pkg cloud-platform-repository-checker.gemspec Rakefile

.PHONY: publish clean
