# BotKenpo

Concierge to assist your reservation to [関東ITソフトウェア健康保険組合 施設・レクリエーション](https://as.its-kenpo.or.jp/).

<a href="https://slack.com/oauth/authorize?client_id=14606570289.291209991584&scope=bot">
  <img alt="Add to Slack" height="40" width="139" src="https://platform.slack-edge.com/img/add_to_slack.png" srcset="https://platform.slack-edge.com/img/add_to_slack.png 1x, https://platform.slack-edge.com/img/add_to_slack@2x.png 2x" />
</a>

## Development

### Use Foreman

```sh
$ bundle exec foreman start
```

### Use Docker env

```sh
$ docker-compose up -d
```

### Configurations

> .dockerenv.secrets

```
LITA_SLACK_TOKEN=<LITA_SLACK_INTEGRATION_TOKEN>
```

Set the environment variable above in the production env.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/tearoom6/bot_kenpo.

