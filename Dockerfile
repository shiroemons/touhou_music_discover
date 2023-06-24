FROM ruby:3.2.2

WORKDIR /app

# Using Node.js v18.x(LTS)
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash -

# Add packages
RUN apt-get update && apt-get install -y \
      git \
      postgresql-client \
      nodejs \
      vim

# Add yarnpkg for assets:precompile
RUN npm install -g yarn
