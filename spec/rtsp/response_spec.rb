require File.dirname(__FILE__) + '/../spec_helper'
require 'rtsp/response'

DESCRIBE_RESPONSE = %Q{ RTSP/1.0 200 OK\r\n
Server: DSS/5.5 (Build/489.7; Platform/Linux; Release/Darwin; )\r\n
Cseq: 1\r\n
Cache-Control: no-cache\r\n
Content-length: 406\r\n
Date: Sun, 23 Jan 2011 00:36:45 GMT\r\n
Expires: Sun, 23 Jan 2011 00:36:45 GMT\r\n
Content-Type: application/sdp\r\n
x-Accept-Retransmit: our-retransmit\r\n
x-Accept-Dynamic-Rate: 1\r\n
Content-Base: rtsp://64.202.98.91:554/gs.sdp/\r\n
\r\n
v=0\r\n
o=- 545877020 467920391 IN IP4 127.0.0.1\r\n
s=Groove Salad from SomaFM [aacPlus]\r\n
i=Downtempo Ambient Groove\r\n
c=IN IP4 0.0.0.0\r\n
t=0 0\r\n
a=x-qt-text-cmt:Orban Opticodec-PC\r\n
a=x-qt-text-nam:Groove Salad from SomaFM [aacPlus]\r\n
a=x-qt-text-inf:Downtempo Ambient Groove\r\n
a=control:*\r\n
m=audio 0 RTP/AVP 96\r\n
b=AS:48\r\n
a=rtpmap:96 MP4A-LATM/44100/2\r\n
a=fmtp:96 cpresent=0;config=400027200000\r\n
a=control:trackID=1\r\n
}

describe RTSP::Response do
  context "describe" do
    before do
      @response = RTSP::Response.new DESCRIBE_RESPONSE
    end

    it "returns a 200 code" do
      @response.code.should == 200
    end

    it "returns 'OK' message" do
      @response.message.should == "OK"
    end

    it "returns all header fields" do
      @response.server.should == "DSS/5.5 (Build/489.7; Platform/Linux; Release/Darwin; )"
      @response.cseq.should == "1"
      @response.cache_control.should == "no-cache"
      @response.content_length.should == "406"
      @response.date.should == "Sun, 23 Jan 2011 00:36:45 GMT"
      @response.expires.should == "Sun, 23 Jan 2011 00:36:45 GMT"
      @response.content_type.should == "application/sdp"
      @response.x_accept_retransmit.should == "our-retransmit"
      @response.x_accept_dynamic_rate.should == "1"
      @response.content_base.should == "rtsp://64.202.98.91:554/gs.sdp/"
    end
  end
end