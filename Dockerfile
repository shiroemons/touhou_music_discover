FROM ruby:3.1.0

WORKDIR /app

# Using Node.js v14.x(LTS)
RUN curl -fsSL https://deb.nodesource.com/setup_14.x | bash -

# Add packages
RUN apt-get update && apt-get install -y \
      git \
      postgresql-client \
      nodejs \
      vim

# Add yarnpkg for assets:precompile
RUN npm install -g yarn
