require 'json'
require 'redis'
require 'kenpo_api'

module Lita
  module Handlers
    class Kenpo < Handler
      RESORT_RESERVE_STEPS = {
        email:         t('step_messages.email'),
        url:           t('step_messages.url'),
        sign_no:       t('step_messages.sign_no'),
        insured_no:    t('step_messages.insured_no'),
        office_name:   t('step_messages.office_name'),
        kana_name:     t('step_messages.kana_name'),
        birth_year:    t('step_messages.birth_year'),
        birth_month:   t('step_messages.birth_month'),
        birth_day:     t('step_messages.birth_day'),
        gender:        t('step_messages.gender'),
        relationship:  t('step_messages.relationship'),
        contact_phone: t('step_messages.contact_phone'),
        postal_code:   t('step_messages.postal_code'),
        state:         t('step_messages.state'),
        address:       t('step_messages.address'),
        join_time:     t('step_messages.join_time'),
        night_count:   t('step_messages.night_count'),
        stay_persons:  t('step_messages.stay_persons'),
        confirm:       t('step_messages.confirm'),
      }
      SPORT_RESERVE_STEPS = {
        email:         t('step_messages.email'),
        url:           t('step_messages.url'),
        sign_no:       t('step_messages.sign_no'),
        insured_no:    t('step_messages.insured_no'),
        office_name:   t('step_messages.office_name'),
        kana_name:     t('step_messages.kana_name'),
        birth_year:    t('step_messages.birth_year'),
        birth_month:   t('step_messages.birth_month'),
        birth_day:     t('step_messages.birth_day'),
        contact_phone: t('step_messages.contact_phone'),
        postal_code:   t('step_messages.postal_code'),
        state:         t('step_messages.state'),
        address:       t('step_messages.address'),
        join_time:     t('step_messages.join_time'),
        use_time_from: t('step_messages.use_time_from'),
        use_time_to:   t('step_messages.use_time_to'),
        confirm:       t('step_messages.confirm'),
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

        def action_button_value
          return nil unless action = @params['actions']&.first
          action['value']
        end

        def action_menu_value
          return nil unless action = @params['actions']&.first
          return nil unless option = action['selected_options']&.first
          option['value']
        end
      end

      on :unhandled_message, :on_message
      def on_message(payload)
        log << "on_message called: #{payload}\n"
        I18n.locale = ENV.fetch('LANG', 'en')
        message = payload[:message]
        user_id = message.source.user.id
        body = message.body

        begin
          session = Session.session_for(redis: redis, user_id: user_id)
          unless session.nil?
            next_message = go_to_next_step(session, body)
            if next_message.nil?
              robot.send_message(message.source, t('messages.complete'))
            elsif next_message.is_a?(Hash)
              attachment = Lita::Adapters::Slack::Attachment.new(t('messages.confirm'), next_message)
              robot.chat_service.send_attachments(message.room_object, attachment)
            else
              robot.send_message(message.source, next_message)
            end
            return
          end

          robot.send_message(message.source, t('messages.help'))
        rescue
          robot.send_message(message.source, t('messages.error'))
        end
      end

      route(/^start$/i, :on_start, help: { 'start' => t('helps.start') })
      def on_start(response)
        I18n.locale = ENV.fetch('LANG', 'en')
        show_menu(response)
        Session.start_session(redis: redis, user_id: response.user&.id)
      end

      http.post '/slack/endpoint/*', :on_request
      def on_request(rack_request, rack_response)
        log << "on_request called: #{rack_request.params['payload']}\n"
        I18n.locale = ENV.fetch('LANG', 'en')
        payload = Payload.new(rack_request.params)
        session = Session.session_for(redis: redis, user_id: payload.user_id)

        if session.nil?
          send_message(payload: payload, message: t('messages.expired'))
          return
        end

        if payload.action_menu_value == 'cancel'
          send_message(payload: payload, message: t('messages.cancel'))
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
        when :confirm
          on_confirm(session, payload)
        end
      end

      Lita.register_handler(self)

      private

      def on_category_select(session, payload)
        session.save(:service_category, payload.action_menu_value)

        case payload.action_menu_value.to_sym
        when :resort_reserve, :resort_search_vacant
          show_resorts(session, payload)
        when :sport_reserve
          show_sports(session, payload)
        else
          # TODO: - Not implemented.
          send_message(payload: payload, message: t('messages.not_yet'))
        end
      end

      def on_resort_select(session, payload)
        session.save(:service, payload.action_menu_value)
        check_service_availability(session, payload.action_menu_value)

        case session.get(:service_category).to_sym
        when :resort_reserve
          step, message = RESORT_RESERVE_STEPS.first
          send_message(payload: payload, message: message)
          session.save(:step, step)
        when :resort_search_vacant
          # TODO: - Not implemented.
          send_message(payload: payload, message: t('messages.not_yet'))
        end
      rescue => e
        send_message(payload: payload, message: e.message)
        session.clear
      end

      def on_sport_select(session, payload)
        session.save(:service, payload.action_menu_value)
        check_service_availability(session, payload.action_menu_value)

        case session.get(:service_category).to_sym
        when :sport_reserve
          step, message = SPORT_RESERVE_STEPS.first
          send_message(payload: payload, message: message)
          session.save(:step, step)
        end
      rescue => e
        send_message(payload: payload, message: e.message)
        session.clear
      end

      def check_service_availability(session, service_name)
        category = KenpoApi::ServiceCategory.find(session.get(:service_category).to_sym)
        group = KenpoApi::ServiceGroup.find(category, service_name)
        raise t('messages.unavailable') unless group&.available?
      end

      def go_to_next_step(session, body)
        service_category = session.get(:service_category).to_sym
        step = session.get(:step).to_sym
        criteria = JSON.parse(session.get(:criteria)) rescue {}
        handle_step(service_category, step, session, body, criteria)

        next_step, message = next_step(service_category, step)
        return nil if next_step.nil?
        session.save(:step, next_step)

        if next_step == :confirm
          return compose_attachment_with_buttons(question:t('messages.review'), callback_id: :review, buttons:[
            compose_button(name: :ok,     text: t('words.ok'),     value: :ok,     style: :danger),
            compose_button(name: :cancel, text: t('words.cancel'), value: :cancel, style: :default),
          ])
        end

        if next_criteria = criteria[next_step]
          message += "\n#{t('words.choose')}: #{next_criteria.to_s}"
        end
        if next_step == :state
          message += "\n#{t('words.refer_to')}: http://nlftp.mlit.go.jp/ksj/gml/codelist/PrefCd.html"
        end
        message
      end

      def handle_step(service_category, step, session, body, criteria)
        if step_criteria = criteria[step]
          raise t('messages.invalid') unless step_criteria.include?(body)
        end

        case step
        when :email
          handle_email_step(session, service_category, body)
        when :url
          handle_url_step(session, service_category, body)
        end

        session.save(step, body)
      end

      def handle_email_step(session, service_category, email)
        case service_category.to_sym
        when :resort_reserve
          KenpoApi::Resort.request_reservation_url(resort_name: session.get(:service), email: email)
        when :sport_reserve
          KenpoApi::Sport.request_reservation_url(sport_name: session.get(:service), email: email)
        end
      end

      def handle_url_step(session, service_category, url)
        criteria =
          case service_category.to_sym
          when :resort_reserve
            KenpoApi::Resort.check_reservation_criteria(url, type: :lottery)
          when :sport_reserve
            KenpoApi::Sport.check_reservation_criteria(url)
          end

        session.save(:criteria, criteria.to_json)
      end

      def on_confirm(session, payload)
        if payload.action_button_value.to_sym == :cancel
          send_message(payload: payload, message: t('messages.cancel'))
          session.clear
          return
        end

        case session.get(:service_category).to_sym
        when :resort_reserve
          reservation_data = compose_resort_reservation_data(session)
          KenpoApi::Resort.apply_reservation(session.get(:url), reservation_data, type: :lottery)
        when :sport_reserve
          reservation_data = compose_sport_reservation_data(session)
          KenpoApi::Sport.apply_reservation(session.get(:url), reservation_data)
        end

        send_message(payload: payload, message: t('messages.complete'))
        session.clear
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
        source = Lita::Source.new(user: response.user, room: response.room)
        robot.send_message(source, t('messages.info'))

        categories = KenpoApi::ServiceCategory.list
        options = categories.map{|category| compose_option(text: category.name, value: category.category_code)}
        options << {text: t('words.cancel'), value: :cancel}
        attachment = compose_attachment_with_menu(
          question: t('questions.menu'),
          callback_id: :category_selection,
          name: 'category',
          options: options,
        )
        attachment = Lita::Adapters::Slack::Attachment.new(t('messages.menu'), attachment)
        robot.chat_service.send_attachments(response.room, attachment)
      end

      def show_resorts(session, payload)
        resort_names = KenpoApi::Resort.resort_names
        options = resort_names.map{|resort_name| compose_option(text: resort_name, value: resort_name)}
        options << {text: t('words.cancel'), value: :cancel}
        attachment = compose_attachment_with_menu(
          question: t('questions.resort'),
          callback_id: :resort_selection,
          name: 'service_group',
          options: options,
        )
        send_attachment(payload: payload, message: t('messages.resort'), attachment: attachment)
      end

      def show_sports(session, payload)
        sport_names = KenpoApi::Sport.sport_names
        options = sport_names.map{|sport_name| compose_option(text: sport_name, value: sport_name)}
        options << {text: t('words.cancel'), value: :cancel}
        attachment = compose_attachment_with_menu(
          question: t('questions.sport'),
          callback_id: :sport_selection,
          name: 'service_group',
          options: options,
        )
        send_attachment(payload: payload, message: t('messages.sport'), attachment: attachment)
      end

      def compose_resort_reservation_data(session)
        data = session.get_all
        {
          sign_no:       data['sign_no'],
          insured_no:    data['insured_no'],
          office_name:   data['office_name'],
          kana_name:     data['kana_name'],
          birth_year:    data['birth_year'],
          birth_month:   data['birth_month'],
          birth_day:     data['birth_day'],
          gender:        data['gender'],
          relationship:  data['relationship'],
          contact_phone: data['contact_phone'],
          postal_code:   data['postal_code'],
          state:         data['state'],
          address:       data['address'],
          join_time:     data['join_time'],
          night_count:   data['night_count'],
          stay_persons:  data['stay_persons'],
          room_persons:  data['stay_persons'],
          meeting_dates: nil,
          must_meeting:  false,
        }
      end

      def compose_sport_reservation_data(session)
        data = session.get_all
        {
          sign_no:       data['sign_no'],
          insured_no:    data['insured_no'],
          office_name:   data['office_name'],
          kana_name:     data['kana_name'],
          birth_year:    data['birth_year'],
          birth_month:   data['birth_month'],
          birth_day:     data['birth_day'],
          contact_phone: data['contact_phone'],
          postal_code:   data['postal_code'],
          state:         data['state'],
          address:       data['address'],
          join_time:     data['join_time'],
          use_time_from: data['use_time_from'],
          use_time_to:   data['use_time_to'],
        }
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

      def compose_attachment_with_menu(question:, fallback:t('messages.fallback'), color:'#4083bc', callback_id:, name:, placeholder:t('messages.placeholder'), options:[])
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

      def compose_attachment_with_buttons(question:, fallback:t('messages.fallback'), color:'#4083bc', callback_id:, buttons:[])
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

      def compose_attachment(question:, fallback:t('messages.fallback'), color:'#4083bc', callback_id:, actions:[])
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
