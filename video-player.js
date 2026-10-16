const WordAheadVideo = {
  videoId:null,frame:null,pending:null,
  valid(id){return /^[A-Za-z0-9_-]{11}$/.test(id||'');},
  native(){return window.webkit?.messageHandlers?.youtubePlayer;},
  show(video){
    if(!this.valid(video?.youtubeId)){this.hide();return;}
    const changed=this.videoId!==video.youtubeId;
    this.videoId=video.youtubeId;
    if(this.native()){this.native().postMessage({action:'show',videoId:this.videoId});return;}
    const host=document.querySelector('#youtube-player-host');host.hidden=false;
    if(!this.frame){
      this.frame=document.createElement('iframe');this.frame.title='YouTube 영상 플레이어';
      this.frame.allow='autoplay; encrypted-media; fullscreen; picture-in-picture';this.frame.allowFullscreen=true;
      this.frame.onload=()=>{if(this.pending)this.send(this.pending);};
      this.frame.src='youtube-player.html';host.append(this.frame);
    }
    if(changed||this.pending?.action==='pause')this.send({action:'load',videoId:this.videoId,start:0,play:false});
  },
  send(command){
    this.pending=command;
    if(this.native()){this.native().postMessage(command);return;}
    this.frame?.contentWindow?.postMessage({type:'wordahead-player',...command},location.origin);
  },
  seek(video,start){
    if(!this.valid(video?.youtubeId)||typeof start!=='number'||!Number.isFinite(start)||start<0)return;
    this.show(video);this.send({action:'seek',videoId:video.youtubeId,start,play:true});
    document.querySelector('#youtube-player-host')?.scrollIntoView({block:'nearest',behavior:'smooth'});
  },
  pause(){this.send({action:'pause'});},
  hide(){
    this.pause();if(this.native())this.native().postMessage({action:'hide'});
    const host=document.querySelector('#youtube-player-host');if(host)host.hidden=true;
  }
};
window.addEventListener('message',event=>{
  if(event.origin!==location.origin||event.data?.type!=='wordahead-player-time'||event.source!==WordAheadVideo.frame?.contentWindow)return;
  window.dispatchEvent(new CustomEvent('wordahead:playbacktime',{detail:{time:event.data.time}}));
});
document.addEventListener('visibilitychange',()=>{if(document.hidden)WordAheadVideo.pause();});
window.addEventListener('pagehide',()=>WordAheadVideo.pause());
