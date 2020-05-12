FROM ruby:2.7-alpine

RUN addgroup -g 1000 -S appgroup \
  && adduser -u 1000 -S appuser -G appgroup \
  && apk update \
  && gem install bundler \
  && bundle config set without 'development'

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY bin/ ./bin
COPY lib/ ./lib

RUN chown -R appuser:appgroup /app

USER 1000

CMD ["ruby", "bin/list-repos.rb"]
