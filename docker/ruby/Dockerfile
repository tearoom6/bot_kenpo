FROM ruby:2.5.0-alpine3.7

ENV LANG=ja_JP.UTF-8\
    APP_ROOT=/bot_kenpo

RUN apk update && \
    apk upgrade && \
    apk add --update --no-cache --virtual build-dependencies build-base && \
    apk add --update --no-cache tzdata git less ncurses && \
    mkdir -p $APP_ROOT

WORKDIR $APP_ROOT
COPY . $APP_ROOT

RUN bundle install --jobs=4 && \
    apk del build-dependencies
