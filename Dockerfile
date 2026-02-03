FROM ruby:3.2.2

RUN apt-get update -qq && apt-get install -y \
  build-essential \
  libpq-dev \
  nodejs \
  redis-server \
  curl

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

EXPOSE 3000

CMD ["bash","-c","redis-server --daemonize yes && bundle exec rails s -b 0.0.0.0 -p 3000"]
