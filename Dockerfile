FROM ruby:2.3-alpine

COPY . /usr/src/app

WORKDIR /usr/src/app

RUN bundle install

CMD ["./daily.rb"]
