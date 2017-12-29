module Lita
  module Handlers
    class Kenpo < Handler
      route(/^check(.*)health(.*)/i, :check_health, help: { 'check_health' => 'Check health.' })
      def check_health(response)
        response.reply('OK')
      end

      Lita.register_handler(self)
    end
  end
end
