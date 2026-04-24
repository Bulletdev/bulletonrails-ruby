FROM ruby:3.4-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ruby-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Gemfile Gemfile.lock* ./
RUN bundle install --without development test

FROM ruby:3.4-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY . .

EXPOSE 9999
CMD ["bundle", "exec", "iodine", "-p", "9999"]
