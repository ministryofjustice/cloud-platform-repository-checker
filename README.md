# cloud-platform-repository-checker

Checks all Cloud Platform repositories for compliance

## Updating

This code is published as a [ruby gem].

To publish a new version:

* Authenticate to `rubygems.org` as `ministryofjustice` (credentials are in LastPass)
* Update the `VERSION` value in the `makefile`
* Run `make publish`

This will repackage the gem using the latest code, and push a new release to
rubygems.org

> Please remember to keep the unit tests in `spec` up to date wrt. your code
> changes.

[ruby gem]: https://rubygems.org/gems/cloud-platform-repository-checker
