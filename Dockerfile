FROM ruby:3.4-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ruby-dev \
    libblas-dev \
    liblapack-dev \
    cmake \
    libgomp1 \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Gemfile Gemfile.lock* ./
RUN bundle install --without development test

FROM ruby:3.4-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    libgomp1 \
    libblas3 \
    liblapack3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY . .

ENV MALLOC_ARENA_MAX=2

EXPOSE 9999
CMD ["bundle", "exec", "iodine", "--yjit", "--yjit-exec-mem-size=8", "-p", "9999"]
