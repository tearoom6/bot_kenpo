require 'json'
require 'redis'
require 'kenpo_api'

module Lita
  module Handlers
    class Kenpo < Handler
      class Session
        def initialize(redis, user_id)
          @redis = redis
          @user_id = user_id
        end

        def self.session_for(redis:, user_id:, ttl: 60)
          instance = self.new(redis, user_id)
          instance.update_ttl(ttl: ttl)
          instance
        end

        def update_ttl(ttl: 60)
          @redis.multi do
            @redis.hset(@user_id, 'user_id', @user_id)
            @redis.expire(@user_id, ttl)
          end
        end

        def save(key, value)
          @redis.hset(@user_id, key, value)
        end

        def get(key)
          @redis.hget(@user_id, key)
        end

        def clear
          @redis.del(@user_id)
        end
      end

      class Payload
        def initialize(params)
          @params = JSON.parse(params['payload'])
        end

        def callback_id
          @params['callback_id'].to_sym
        end

        def response_url
          @params['response_url']
        end

        def team_id
          @params['team']['id']
        end

        def user_id
          @params['user']['id']
        end

        def room_id
          @params['channel']['id']
        end

        def action_name
          return nil unless action = @params['actions']&.first
          action['name']
        end

        def action_value
          return nil unless action = @params['actions']&.first
          return nil unless option = action['selected_options']&.first
          option['value']
        end
      end

      on :unhandled_message, :show_help
      def show_help(payload)
        message = payload[:message]
        robot.send_message(message.source, "Try 'help' for a list of available commands.")
      end

      route(/^start$/i, :on_start, help: { 'start' => 'Show menu.' })
      def on_start(response)
        show_menu(response)
        Session.session_for(redis: redis, user_id: response.user&.id)
      end

      http.post '/slack/endpoint/*', :on_request
      def on_request(rack_request, rack_response)
        log << "on_request called: #{rack_request.params['payload']}\n"
        payload = Payload.new(rack_request.params)
        session = Session.session_for(redis: redis, user_id: payload.user_id)

        if payload.action_value == 'cancel'
          send_message(payload: payload, message: 'See you again!')
          session.clear
          return
        end

        case payload.callback_id
        when :category_selection
          on_category_select(session, payload)
        end
      end

      Lita.register_handler(self)

      private

      def on_category_select(session, payload)
        session.save('service_category', payload.action_value)

        case payload.action_value.to_sym
        when :resort_reserve, :resort_search_vacant
          show_resorts(session, payload)
        when :sport_reserve
          show_sports(session, payload)
        else
          send_message(payload: payload, message: "This feature is not implemented yet. Please contribute to the development.\nhttps://github.com/tearoom6/bot_kenpo")
        end
      end

      def show_menu(response)
        categories = KenpoApi::ServiceCategory.list
        options = categories.map{|category| compose_option(text: category.name, value: category.category_code)}
        options << {text: 'Cancel', value: :cancel}
        attachment = compose_attachment_with_menu(
          question: 'Choose the service to want.',
          callback_id: :category_selection,
          name: 'category',
          options: options,
        )
        attachment = Lita::Adapters::Slack::Attachment.new('What service do you want?', attachment)
        robot.chat_service.send_attachments(response.room, attachment)
      end

      def show_resorts(session, payload)
        resort_names = KenpoApi::Resort.resort_names
        options = resort_names.map{|resort_name| compose_option(text: resort_name, value: resort_name)}
        options << {text: 'Cancel', value: :cancel}
        attachment = compose_attachment_with_menu(
          question: 'Choose resort to apply reservation for.',
          callback_id: :resort_selection,
          name: 'service_group',
          options: options,
        )
        send_attachment(payload: payload, message: 'What resort do you want?', attachment: attachment)
      end

      def show_sports(session, payload)
        sport_names = KenpoApi::Sport.sport_names
        options = sport_names.map{|sport_name| compose_option(text: sport_name, value: sport_name)}
        options << {text: 'Cancel', value: :cancel}
        attachment = compose_attachment_with_menu(
          question: 'Choose sport facility to apply reservation for.',
          callback_id: :sport_selection,
          name: 'service_group',
          options: options,
        )
        send_attachment(payload: payload, message: 'What sport facility do you want?', attachment: attachment)
      end

      def send_attachment(payload:, message:, attachment:)
        message_body = compose_message_body(message: message, attachments: [attachment])
        http.post(payload.response_url, message_body, {'Content-Type' => 'application/json'})
      end

      def send_message(payload:, message:)
        message_body = compose_message_body(message: message)
        http.post(payload.response_url, message_body, {'Content-Type' => 'application/json'})
      end

      def compose_message_body(message:, attachments:[], response_type: :in_channel, replace_original: true)
        {
          text: message,
          attachments: attachments,
          response_type: response_type,
          replace_original: replace_original,
        }.to_json
      end

      def compose_attachment_with_menu(question:, fallback:'Something wrong...', color:'#4083bc', callback_id:, name:, placeholder:'Choose...', options:[])
        compose_attachment(question: question, fallback: fallback, color: color, callback_id: callback_id, actions: [
          {
            name: name,
            text: placeholder,
            type: :select,
            options: options,
          },
        ])
      end

      def compose_option(text:, value:)
        {
          text: text,
          value: value,
        }
      end

      def compose_attachment_with_buttons(question:, fallback:'Something wrong...', color:'#4083bc', callback_id:, buttons:[])
        compose_attachment(question: question, fallback: fallback, color: color, callback_id: callback_id, actions: buttons)
      end

      def compose_button(name:, text:, value:, style: :default)
        {
          name: name,
          text: text,
          type: :button,
          value: value,
          style: style,
        }
      end

      def compose_attachment(question:, fallback:'Something wrong...', color:'#4083bc', callback_id:, actions:[])
        {
          text: question,
          fallback: fallback,
          color: color,
          attachment_type: :default,
          callback_id: callback_id,
          actions: actions,
        }
      end

    end
  end
end
