require 'socket'
require 'tempfile'
require 'timeout'
require 'uri'

require File.expand_path(File.dirname(__FILE__) + '/request')
require File.expand_path(File.dirname(__FILE__) + '/helpers')
require File.expand_path(File.dirname(__FILE__) + '/exception')
require File.expand_path(File.dirname(__FILE__) + '/global')

module RTSP

  # Allows for pulling streams from an RTSP server.
  class Client
    include RTSP::Helpers
    include RTSP::Global

    attr_reader :options
    attr_reader :server_uri
    attr_reader :cseq
    attr_reader :session
    attr_accessor :tracks

    # @param [String] rtsp_url URL to the resource to stream.  If no scheme is given,
    # "rtsp" is assumed.  If no port is given, 554 is assumed.  If no path is
    # given, "/stream1" is assumed.
    def initialize(rtsp_url, args={})
      @server_uri = build_resource_uri_from rtsp_url
      @args = args

      @cseq = 1
      #@tracks = options[:tracks] || ["/track1"]

=begin
      if options[:capture_file_path] && options[:capture_duration]
        @capture_file_path = options[:capture_file_path]
        @capture_duration = options[:capture_duration]
        setup_capture
      end
=end
      #binding.pry
    end

    # The URL for the RTSP server to talk to can change if multiple servers are
    # involved in delivering content.  This method can be used to change the
    # server to talk to on the fly.
    #
    # @param [String] new_url The new server URL to use to communicate over.
    def server_url=(new_url)
      @server_uri = build_resource_uri_from new_url
    end

    # Sends an OPTIONS message to the server specified by @server_uri.  Sets
    # @supported_methods based on the list of supported methods returned in the
    # Public headers.  Lastly, if the response was an OK, it increases the @cseq
    # value so that the next uses that.
    #
    # @param [Hash] additional_headers
    # @return [RTSP::Response]
    def options additional_headers={}
      headers = ( { :cseq => @cseq }).merge(additional_headers)

      begin
        response = RTSP::Request.execute(@args.merge(
            :method => :options,
            :resource_url => @server_uri,
            :headers => headers
        ))

        @supported_methods = extract_supported_methods_from response.public
        compare_sequence_number response.cseq
        @cseq += 1
      rescue RTSPException => ex
        puts "Got #{ex.message}"
        puts ex.backtrace
      end

      response
    end

    # TODO: get tracks, IP's, ports, multicast/unicast
    # @param [Hash] additional_headers
    # @return [RTSP::Response]
    def describe additional_headers={}
      headers = ( { :cseq => @cseq }).merge(additional_headers)

      begin
        response = RTSP::Request.execute(@args.merge(
            :method => :describe,
            :resource_url => @server_uri,
            :headers => headers
        ))

        compare_sequence_number response.cseq
        @cseq += 1
        @session_description = response.body
        @content_base = build_resource_uri_from response.content_base

        @media_control_tracks = media_control_tracks
        @aggregate_control_track = aggregate_control_track
      rescue RTSPException => ex
        puts "Got #{ex.message}"
        puts ex.backtrace
      end

      response
    end

    # @param [String] url A track or presentation URL to pause.
    # @param [SDP::Description] description
    # @param [Hash] additional_headers
    # @return [RTSP::Response]
    def announce(request_url, description, additional_headers={})
      headers = ( { :cseq => @cseq }).merge(additional_headers)

      begin
        response = RTSP::Request.execute(@args.merge(
            :method => :announce,
                :resource_url => request_url,
                :headers => headers,
                :body => description.to_s
        ))

        compare_sequence_number response.cseq
        @cseq += 1
      rescue RTSPException => ex
        puts "Got #{ex.message}"
        puts ex.backtrace
      end

      response
    end

    # TODO: parse Transport header (http://tools.ietf.org/html/rfc2326#section-12.39)
    # TODO: @session numbers are relevant to tracks, and a client can play multiple tracks at the same time.
    #
    # @param [String] track
    # @param [Hash] additional_headers
    # @return [RTSP::Response] The response formatted as a Hash.
    def setup track, additional_headers={}
      headers = ( { :cseq => @cseq }).merge(additional_headers)

      begin
        response = RTSP::Request.execute(@args.merge(
            :method => :setup,
            :resource_url => track,
            :headers => headers
        ))

        compare_sequence_number response.cseq
        @session = response.session
        @cseq += 1
      rescue RTSPException => ex
        puts "Got #{ex.message}"
        puts ex.backtrace
      end

      response
    end

    # @param [String] track
    # @param [Hash] additional_headers
    # @return [RTSP::Response]
    # TODO: If Response !=200, that should be an exception.  Handle that exception then reset CSeq and session.
    def play track, additional_headers={}
      if @session
        headers = ( { :cseq => @cseq, :session => @session }).merge(additional_headers)
      else
        raise RTSPException, "Session number not retrieved from server yet.  Run SETUP first."
      end

      begin
        response = RTSP::Request.execute(@args.merge(
            :method => :play,
            :resource_url => track,
            :headers => headers
        ))

        compare_sequence_number response.cseq
        compare_session_number response.session
        @cseq += 1
      rescue RTSPException => ex
        puts "Got #{ex.message}"
        puts ex.backtrace
      end

=begin
      if @capture_file_path
        begin
          Timeout::timeout(@capture_duration) do
            while data = @capture_socket.recvfrom(102400).first
              @logger.debug "data size = #{data.size}"
              @capture_file_path.write data
            end
          end
        rescue Timeout::Error
          # Blind rescue
        end

        @capture_socket.close
      end
=end

      response
    end

    # @param [String] url A track or presentation URL to pause.
    # @param [Hash] additional_headers
    # @return [RTSP::Response]
    def pause(url, additional_headers={})
      if @session
        headers = ( { :cseq => @cseq, :session => @session }).merge(additional_headers)
      else
        raise RTSPException, "Session number not retrieved from server yet.  Run SETUP first."
      end

      begin
        response = RTSP::Request.execute(@args.merge(
            :method => :pause,
            :resource_url => url,
            :headers => headers
        ))

        compare_sequence_number response.cseq
        compare_session_number response.session
        @cseq += 1
      rescue RTSPException => ex
        puts "Got #{ex.message}"
        puts ex.backtrace
      end

      response
    end

    # @return [RTSP::Response]
    def teardown track, additional_headers={}
      if @session
        headers = ( { :cseq => @cseq, :session => @session }).merge(additional_headers)
      else
        raise RTSPException, "Session number not retrieved from server yet.  Run SETUP first."
      end

      begin
        response = RTSP::Request.execute(@args.merge(
            :method => :teardown,
            :resource_url => track,
            :headers => headers
        ))

        if response.code != 200
          message = "#{response.code}: #{response.message}\nAllowed methods: #{response.allow}"
          raise RTSPException, message
        end

        compare_sequence_number response.cseq
        compare_session_number response.session
        @cseq = 1
        @session = 0
      rescue RTSPException => ex
        puts "Got #{ex.message}"
        puts ex.backtrace
      end
      #@socket.close if @socket.open?
      #@socket = nil

      response
    end

    # @return [RTSP::Response]
    def get_parameter(track, body, additional_headers={})
      if @session
        headers = ( { :cseq => @cseq,
            :session => @session,
            :content_length => body.size
        }).merge(additional_headers)
      else
        raise RTSPException, "Session number not retrieved from server yet.  Run SETUP first."
      end

      begin
        response = RTSP::Request.execute(@args.merge(
            :method => :get_parameter,
            :resource_url => track,
            :headers => headers,
            :body => body
        ))

        if response.code != 200
          message = "#{response.code}: #{response.message}\nAllowed methods: #{response.allow}"
          raise RTSPException, message
        end

        compare_sequence_number response.cseq
        compare_session_number response.session
        @cseq = 1
        @session = 0
      rescue RTSPException => ex
        puts "Got #{ex.message}"
        puts ex.backtrace
      end

      response
    end

    def aggregate_control_track
      aggregate_control = @session_description.attributes.find_all do |a|
        a[:attribute] == "control"
      end

      "#{@content_base}#{aggregate_control.first[:value]}"
    end

    # Extracts the value of the "control" attribute from all media sections of
    # the session description (SDP).  You have to call the #describe method in
    # order to get the session description info.
    #
    # @return [Array] The tracks made up of the content base + control track
    # value.
    def media_control_tracks
      tracks = []
      @session_description.media_sections.each do |media_section|
        media_section[:attributes].each do |a|
          tracks << "#{@content_base}#{a[:value]}" if a[:attribute] == "control"
        end
      end

      tracks
    end

    # Compares the sequence number passed in to the current client sequence
    # number (@cseq) and raises if they're not equal.  If that's the case, the
    # server responded to a different request.
    #
    # @param [Fixnum] server_cseq Sequence number returned by the server.
    # @raise [RTSPException]
    def compare_sequence_number server_cseq
      if @cseq != server_cseq
        message = "Sequence number mismatch.  Client: #{@cseq}, Server: #{server_cseq}"
        raise RTSPException, message
      end
    end

    # Compares the session number passed in to the current client session
    # number (@session) and raises if they're not equal.  If that's the case, the
    # server responded to a different request.
    #
    # @param [Fixnum] server_session Session number returned by the server.
    # @raise [RTSPException]
    def compare_session_number server_session
      if @session != server_session
        message = "Session number mismatch.  Client: #{@session}, Server: #{server_session}"
        raise RTSPException, message
      end
    end

    # Takes the methods returned from the Public header from an OPTIONS response
    # and puts them to an Array.
    #
    # @param [String] method_list The string returned from the server containing
    # the list of methods it supports.
    # @return [Array<Symbol>] The list of methods as symbols.
    def extract_supported_methods_from method_list
      method_list.downcase.split(', ').map { |m| m.to_sym }
    end

    def setup_capture
      @capture_file = File.open(@capture_file_path, File::WRONLY|File::EXCL|File::CREAT)
      @capture_socket = UDPSocket.new
      @capture_socket.bind "0.0.0.0", @server_uri.port
    end
  end
end