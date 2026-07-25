FROM ruby:4.0.6

WORKDIR /app

# Using Node.js v24.x(LTS)
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash -

# Add packages
RUN apt-get update && apt-get install -y \
      git \
      postgresql-client \
      nodejs \
      vim

# Add yarnpkg for assets:precompile
RUN npm install -g yarn@1.22.22
