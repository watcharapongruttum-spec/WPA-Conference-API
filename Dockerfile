FROM ruby:3.2.2

RUN apt-get update -qq && apt-get install -y \
  build-essential \
  libpq-dev \
  nodejs \
  curl

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

# ให้สิทธิ์ script
RUN chmod +x bin/render-start

EXPOSE 3000

# ใช้ startup script แทน
CMD ["bin/render-start"]