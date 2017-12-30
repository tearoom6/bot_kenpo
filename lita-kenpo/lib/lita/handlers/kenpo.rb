require 'json'
require 'kenpo_api'

module Lita
  module Handlers
    class Kenpo < Handler

      on :unhandled_message, :show_help
      def show_help(payload)
        message = payload[:message]
        robot.send_message(message.source, "Try 'help' for a list of available commands.")
      end

      route(/^start$/i, :show_menu, help: { 'start' => 'Show menu.' })
      def show_menu(response)
        categories = KenpoApi::ServiceCategory.list
        options = categories.map{|category| compose_option(text: category.name, value: category.category_code)}
        options << {text: 'Cancel', value: :cancel}
        message = compose_form_with_menu(
          question: 'Choose the service to want.',
          callback_id: :category_selection,
          name: 'category',
          options: options,
        )
        attachment = Lita::Adapters::Slack::Attachment.new('What service do you want?', message)
        robot.chat_service.send_attachments(response.room, attachment)
      end

      Lita.register_handler(self)

      private

      def compose_form_with_menu(question:, fallback:'Something wrong...', color:'#4083bc', callback_id:, name:, placeholder:'Choose...', options:[])
        compose_form(question: question, fallback: fallback, color: color, callback_id: callback_id, actions: [
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

      def compose_form_with_buttons(question:, fallback:'Something wrong...', color:'#4083bc', callback_id:, buttons:[])
        compose_form(question: question, fallback: fallback, color: color, callback_id: callback_id, actions: buttons)
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

      def compose_form(question:, fallback:'Something wrong...', color:'#4083bc', callback_id:, actions:[])
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
