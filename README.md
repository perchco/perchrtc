PerchRTC
========

This iOS sample demonstrates multi-party video conferencing using WebRTC and the XirSys cloud infrastructure.

* Integrates WebRTC using a universal build packaged as a CocoaPod.
* Uses Signaling and ICE Servers provided by [XirSys](http://xirsys.com). Requires a free account & credentials to run.
* Uses the [XirSys API client project](https://github.com/samsymons/XirSys).
* Includes `XSPeerClient`, a websocket signaling client. (to be migrated to the XirSys project)
* Includes `PHQuartzVideoView`, a video renderer which uses a CALayer to display CGImages.
* Includes `PHSampleBufferRenderer` & `PHSampleBufferView` which render video using AVSampleBufferDisplayLayer.
* An AVFoundation based capture pipeline with device controls and flexible capture format support.
* A custom C++ cricket::VideoCapturer to interface with WebRTC.
* Basic support for camera rotation & audio muting.
* iOS simulator can receive both audio & video, and transmit audio.
* iOS devices support full duplex audio & video using the front camera.

## Installation

PerchRTC uses [CocoaPods](https://cocoapods.org/) 0.37.2 to install its dependencies.

To get started, clone the repo and install its dependencies:

```
git clone git@github.com:perchco/perchrtc.git PerchRTC
cd PerchRTC
pod install
```

This demo assumes a single XirSys room, domain, and application. Here's how to configure PerchRTC to use your XirSys account:

1. Sign up for a free account on the [XirSys website](http://xirsys.com).
2. Accept the activation email, and sign in to your account.
3. Configure your application, domain, and room in the dashboard.
4. Enter your credentials, including the room name, in `PHCredentials.h`.

Only XirSys v2 accounts are supported. If you wish to use PerchRTC with a XirSys v1 account, please try the 0.1 tag.

## Usage

From the perspective of our view controller, video chatting isn’t hard at all.

First, we start by creating a PHConnectionBroker instance. This class is going to perform most of the heavy lifting of discovering peers, and negotiating connections with them. For simplicity’s sake, we’ve hardcoded the app to work in a single room, which we ask the broker to join.

``` obj-c
XSRoom *room = [[XSRoom alloc] initWithAuthToken:nil username:name andRoomName:roomName];
PHConnectionBroker *connectionBroker = [[PHConnectionBroker alloc] initWithDelegate:self];

[connectionBroker addObserver:self forKeyPath:@"peerConnectionState" options:NSKeyValueObservingOptionOld context:NULL];
[connectionBroker connectToRoom:room];
```

Next, wait for the local stream to become ready. In order to display the video from a stream we need a PHRenderer. Lets create the local renderer immediately, and assign ourselves as its delegate. We also add a tap gesture recognizer so the user can mute and unmute the local feed.

``` obj-c
- (void)connectionBroker:(PHConnectionBroker *)broker didAddLocalStream:(RTCMediaStream *)localStream
{
    // Prepare a renderer for the local stream.
    
    self.localRenderer = [self rendererForStream:localStream];
    UIView *theView = self.localRenderer.rendererView;

    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleAudioTap:)];
    [theView addGestureRecognizer:tapRecognizer];
}
```

As the peer discovery and negotiation process continues, remote streams will become available. Let's add renderers for those as well.

``` obj-c
- (void)connectionBroker:(PHConnectionBroker *)broker didAddStream:(RTCMediaStream *)remoteStream
{
    // Prepare a renderer for the remote stream.
    
    id<PHRenderer> remoteRenderer = [self rendererForStream:remoteStream];
    UIView *theView = remoteRenderer.rendererView;

    [self.remoteRenderers addObject:remoteRenderer];

    UITapGestureRecognizer *tapToZoomRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleZoomTap:)];
    tapToZoomRecognizer.numberOfTapsRequired = 2;
    [theView addGestureRecognizer:tapToZoomRecognizer];
}

``` 

Once a renderer receives its first frame, it's time to show it in our view. As the dimensions of the rendered streams change, we should make sure to keep our layout up to date.

``` obj-c
- (void)rendererDidReceiveVideoData:(id<PHRenderer>)renderer
{
    if (renderer == self.localRenderer) {
        [self showLocalRenderer];
    }
    
    ...
}

- (void)renderer:(id<PHRenderer>)renderer streamDimensionsDidChange:(CGSize)dimensions
{
    [self.view setNeedsLayout];
}
```

As peers come and go, remote streams will be removed from the connection broker's set.

``` obj-c
- (void)connectionBroker:(PHConnectionBroker *)broker didRemoveStream:(RTCMediaStream *)remoteStream
{
    [self removeRendererForStream:remoteStream];

    if ([broker.remoteStreams count] == 0) {
        [self showWaitingInterfaceWithDefaultMessage];
    }
}
```

That about covers the basics. Things may seem simple on the surface, but that's because the signaling layer, and media engine are making a number of decisions on our behalf. Furthermore, our renderers are dealing with the complexity of drawing decoded frames, abstracting the result into a UIView.

###Signaling

Signaling is a critical part of any WebRTC application, and one that is (by definition) left up to the application developer. While the WebRTC standard defines how connections are established and how media is exchanged, it does not answer the question of “which peers want to connect”. Initially, this might seem like a drawback, but in practice this means that signaling can be customized exactly for your use case.

In this example, we use the XirSys WebSocket signaling server. This server employs a custom JSON-based messaging protocol, and a chat room model to allow for user discovery and communication. For our video conferencing use case we only need to exchange a few different types of messages:

| Message | Payload |
|:---:|:---:|
|Offer|A session description offer to connect, or renegotiate an existing connection.|
|Answer|A session description answer created in response to the offer.|
|ICE|A media transport & address/port candidate generated by the ICE agent.|
|Bye|Terminates a connection.|

XSPeerClient performs the role of signaling client, establishing a WebSocket connection to the XirSys signaling server. The client exposes a simple API via the XSPeerClientDelegate, and XSRoomObserver protocols.

``` obj-c
@protocol XSRoomObserver <NSObject>

- (void)didJoinRoom:(XSRoom *)room;
- (void)didLeaveRoom:(XSRoom *)room;

- (void)room:(XSRoom *)room didAddPeer:(XSPeer *)peer;
- (void)room:(XSRoom *)room didRemovePeer:(XSPeer *)peer;

- (void)room:(XSRoom *)room didReceiveMessage:(XSMessage *)message;

@end
```

For a more in depth discussion of the sample code please visit our [PerchRTC blog series](https://perch.co/blog/perchrtc-released/).

## WebRTC Build Notes

* Chrome m45 branch.
* Capture pipeline modified to use pooled memory.
* Supports Armv7, Arm64, x86, and x86-64 architectures (release mode).
* Built against the iOS 8.4 SDK using the system Clang compiler (not the Chromium default).
* Based upon the fantastic [PristineIO WebRTC scripts](https://github.com/pristineio/webrtc-build-scripts).