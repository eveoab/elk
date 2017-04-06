require "time"

module Elk
  # Used to send SMS through 46elks SMS-gateway
  class SMS
    attr_reader :from, :to, :message, :image, :message_id, :created_at,
                :loaded_at, :direction, :status, :client #:nodoc:

    def initialize(parameters) #:nodoc:
      set_parameters(parameters)
    end

    def set_parameters(parameters) #:nodoc:
      @from       = parameters[:from]
      @to         = parameters[:to]
      @message    = parameters[:message]
      @image      = parameters[:image]
      @message_id = parameters[:id]
      @created_at = Time.parse(parameters[:created]) if parameters[:created]
      @loaded_at  = Time.now
      @direction  = parameters[:direction]
      @status     = parameters[:status]
      @client     = parameters.fetch(:client) { Elk.client }
    end

    # Reloads a SMS from server
    def reload
      response = @client.get("/SMS/#{self.message_id}")
      self.set_parameters(Elk::Util.parse_json(response.body))
      response.code == 200
    end

    class << self
      include Elk::Util

      # Send SMS
      # Required parameters
      #
      # * :from - Either the one of the allocated numbers or arbitrary alphanumeric string of at most 11 characters
      # * :to - Any phone number capable of receiving SMS. Multiple numbers can be given as Array or comma separated String
      # * :message - Any UTF-8 text Splitting and joining multi-part SMS messages are automatically handled by the API
      #
      # Optional parameters
      # * :flash - if set to non-false value SMS is sent as a "Flash SMS"
      # * :client - `Elk::Client` instance
      # * :whendelivered - Callback URL that will receive a POST after delivery
      #
      def send(parameters)
        verify_parameters(parameters, [:from, :message, :to])

        client = parameters.fetch(:client) { Elk.client }

        arguments = {}
        arguments[:from]     = parameters.fetch(:from)
        arguments[:to]       = Array(parameters.fetch(:to)).join(",")
        arguments[:message]  = parameters.fetch(:message)
        
        if parameters.fetch(:flash) { false }
          arguments[:flashsms] = "yes"
        end

        if parameters.key?(:whendelivered)
          arguments[:whendelivered] = parameters.fetch(:whendelivered)
        end

        if parameters.key?(:image)
          arguments[:image] = parameters.fetch(:image)
        end

        check_sender_limit(arguments[:from])

        endpoint = parameters.key?(:image) ? "/MMS" : "/SMS"
        response = client.post(endpoint, arguments)
        parsed_response = Elk::Util.parse_json(response.body)

        if multiple_recipients?(arguments[:to])
          parsed_response.each { |m| m[:client] = client }
          instantiate_multiple(parsed_response)
        else
          parsed_response[:client] = client
          self.new(parsed_response)
        end
      end

      # Get outgoing and incomming messages. Limited by the API to 100 latest
      #
      # Optional parameters
      # * :client - Elk::Client instance
      #
      def all(parameters = {})
        client = parameters.fetch(:client) { Elk.client }
        response = client.get("/SMS")
        messages = Elk::Util.parse_json(response.body).fetch(:data).each { |m| m[:client] = client }
        instantiate_multiple(messages)
      end

      private
      def instantiate_multiple(messages)
        messages.map { |message| self.new(message) }
      end

      def multiple_recipients?(to)
        to.split(",").length > 1
      end

      # Warn if the from string will be capped by the sms gateway
      def check_sender_limit(from)
        if from.to_s.match(/^(\w{11,})$/)
          warn "SMS 'from' value #{from} will be capped at 11 chars"
        end
      end
    end
  end
end
