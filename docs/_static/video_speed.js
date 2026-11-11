// Speed buttons (1x, 1.5x, 2x) under every video in the docs. Captions follow
// the video, so they keep pace at any speed.
document.addEventListener("DOMContentLoaded", () => {
  for (const video of document.querySelectorAll("video")) {
    const bar = document.createElement("div");
    bar.className = "video-speed";
    bar.setAttribute("role", "group");
    bar.setAttribute("aria-label", "Playback speed");
    for (const rate of [1, 1.5, 2]) {
      const button = document.createElement("button");
      button.type = "button";
      button.textContent = `${rate}×`;
      button.setAttribute("aria-pressed", String(rate === 1));
      button.addEventListener("click", () => {
        video.playbackRate = rate;
        for (const other of bar.children) {
          other.setAttribute("aria-pressed", String(other === button));
        }
      });
      bar.append(button);
    }
    video.after(bar);
  }
});
