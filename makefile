IMAGE := ministryofjustice/cloud-platform-repository-checker:1.1

.built-image: Dockerfile makefile Gemfile Gemfile.lock bin/*.rb lib/*.rb
	docker build -t $(IMAGE) .
	docker push $(IMAGE)
	touch .built-image

build: .built-image

run: .built-image
	docker run --rm \
		-e GITHUB_TOKEN=$${GITHUB_TOKEN} \
		-e ORGANIZATION=$${ORGANIZATION} \
		-e TEAM=$${TEAM} \
		-e REGEXP=$${REGEXP} \
		$(IMAGE)
