require 'json'
require 'redis'
require 'kenpo_api'

module Lita
  module Handlers
    class Kenpo < Handler
      RESORT_RESERVE_STEPS = {
        email:         'Input your email address to receive application url for.',
        url:           'Check the email & Input the application url.',
        sign_no:       'Input your sign number.',
        insured_no:    'Input your insured number.',
        office_name:   'Input your office name.',
        kana_name:     'Input your name in Katakana.',
        birth_year:    'Input your birth year.',
        birth_month:   'Input your birth month.',
        birth_day:     'Input your birth day of the month.',
        gender:        'Input your gender.',
        relationship:  'Input your relationship to the insured person.',
        contact_phone: 'Input your phone number.',
        postal_code:   'Input your postal code.',
        state:         'Input your state.',
        address:       'Input your address.',
      }
      SPORT_RESERVE_STEPS = {
        email: 'Input your email address to receive application url for.',
        url:   'Check the email & Input the application url.',
        # TODO: - Not implemented.
      }

      class Session
        def initialize(redis, user_id)
          @redis = redis
          @user_id = user_id
        end

        def self.start_session(redis:, user_id:, ttl: 60)
          instance = self.new(redis, user_id)
          instance.update_ttl(ttl: ttl)
          instance
        end

        def self.session_for(redis:, user_id:, ttl: 60)
          instance = self.new(redis, user_id)
          return nil unless instance.exists?
          instance.update_ttl(ttl: ttl)
          instance
        end

        def exists?
          @redis.exists(@user_id)
        end

        def update_ttl(ttl: 60)
          @redis.multi do
            @redis.hset(@user_id, 'user_id', @user_id)
            @redis.expire(@user_id, ttl)
          end
        end

        def save(field, value)
          @redis.hset(@user_id, field, value)
        end

        def get(field)
          @redis.hget(@user_id, field)
        end

        def get_all
          @redis.hvals(@user_id)
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

      on :unhandled_message, :on_message
      def on_message(payload)
        log << "on_message called: #{payload}\n"
        message = payload[:message]
        user_id = message.source.user.id
        body = message.body

        session = Session.session_for(redis: redis, user_id: user_id)
        unless session.nil?
          next_message = go_to_next_step(session, body)
          if next_message.nil?
            robot.send_message(message.source, 'I have received your application! Thank you!')
          else
            robot.send_message(message.source, next_message)
          end
          return
        end

        robot.send_message(message.source, "Try 'help' for a list of available commands.")
      end

      route(/^start$/i, :on_start, help: { 'start' => 'Show menu.' })
      def on_start(response)
        show_menu(response)
        Session.start_session(redis: redis, user_id: response.user&.id)
      end

      http.post '/slack/endpoint/*', :on_request
      def on_request(rack_request, rack_response)
        log << "on_request called: #{rack_request.params['payload']}\n"
        payload = Payload.new(rack_request.params)
        session = Session.session_for(redis: redis, user_id: payload.user_id)

        if session.nil?
          send_message(payload: payload, message: 'Session expired. Please start again!')
          return
        end

        if payload.action_value == 'cancel'
          send_message(payload: payload, message: 'See you again!')
          session.clear
          return
        end

        case payload.callback_id
        when :category_selection
          on_category_select(session, payload)
        when :resort_selection
          on_resort_select(session, payload)
        when :sport_selection
          on_sport_select(session, payload)
        end
      end

      Lita.register_handler(self)

      private

      def on_category_select(session, payload)
        session.save(:service_category, payload.action_value)

        case payload.action_value.to_sym
        when :resort_reserve, :resort_search_vacant
          show_resorts(session, payload)
        when :sport_reserve
          show_sports(session, payload)
        else
          # TODO: - Not implemented.
          send_message(payload: payload, message: "This feature is not implemented yet. Please contribute to the development.\nhttps://github.com/tearoom6/bot_kenpo")
        end
      end

      def on_resort_select(session, payload)
        session.save(:service, payload.action_value)

        case session.get(:service_category).to_sym
        when :resort_reserve
          step, message = RESORT_RESERVE_STEPS.first
          send_message(payload: payload, message: message)
          session.save(:step, step)
        when :resort_search_vacant
          # TODO: - Not implemented.
        end
      end

      def on_sport_select(session, payload)
        session.save(:service, payload.action_value)

        case session.get(:service_category).to_sym
        when :sport_reserve
          step, message = SPORT_RESERVE_STEPS.first
          send_message(payload: payload, message: message)
          session.save(:step, step)
        end
      end

      def go_to_next_step(session, body)
        service_category = session.get(:service_category).to_sym
        step = session.get(:step).to_sym
        handle_step(service_category, step, session, body)

        next_step, message = next_step(service_category, step)
        return nil if next_step.nil?
        session.save(:step, next_step)
        message
      end

      def handle_step(service_category, step, session, body)
        # TODO: - Not implemented.
        session.save(step, body)
      end

      def next_step(service_category, current_step)
        steps = steps(service_category)

        index = steps.find_index{|key, _| key == current_step.to_sym}
        keys = steps.keys
        return nil if index >= keys.size
        values = steps.values
        [keys[index], values[index]]
      end

      def steps(service_category)
        case service_category.to_sym
        when :resort_reserve
          RESORT_RESERVE_STEPS
        when :sport_reserve
          SPORT_RESERVE_STEPS
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
