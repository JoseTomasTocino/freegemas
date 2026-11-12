'use strict';

/* Freegemas — Commander X16 web player.
 *
 * Loads the official x16-emulator WebAssembly build (r49), copies the generated
 * x16/hostfs files into the emulator's virtual drive, and starts boot.prg. The
 * page itself has no copy of the emulator: it is downloaded by
 * x16/web/assemble.mjs when the static site is built.
 */

var canvas = document.getElementById('canvas');
var boot = document.getElementById('boot');
var playBtn = document.getElementById('play');
var bootError = document.getElementById('bootError');
var errorBox = document.getElementById('error');
var statusEl = document.getElementById('status');
var soundBtn = document.getElementById('sound');
var fullscreenBtn = document.getElementById('fullscreen');
var restartBtn = document.getElementById('restart');

var started = false;
var running = false;
var failed = false;
var soundOn = false;
var autoStart = new URLSearchParams(location.search).has('auto');

function say(text) {
  statusEl.textContent = text;
}

function fail(message) {
  failed = true;
  running = false;
  say('Unable to run the game.');
  if (!boot.hidden) {
    bootError.textContent = message + ' Use “Restart” to try again.';
    bootError.hidden = false;
  } else {
    errorBox.textContent = message + ' Use “Restart” to reload the page.';
    errorBox.hidden = false;
  }
  playBtn.disabled = true;
  soundBtn.disabled = true;
  fullscreenBtn.disabled = true;
}

/* The emulator reads this global configuration before starting main(). */
var Module = {
  canvas: canvas,
  arguments: ['-prg', 'boot.prg', '-run', '-capture', '-ram', '512', '-scale', '1',
              '-quality', 'nearest', '-keymap', 'en-us'],
  locateFile: function (name) { return 'emulator/' + name; },
  preRun: [function () {
    if (typeof ENV !== 'undefined') ENV.SDL_EMSCRIPTEN_KEYBOARD_ELEMENT = '#canvas';
    addRunDependency('freegemas-files');
    say('Loading the game files…');
    fetch('game/manifest.json')
      .then(function (response) {
        if (!response.ok) throw new Error('game/manifest.json (' + response.status + ')');
        return response.json();
      })
      .then(function (manifest) {
        var done = 0;
        var total = manifest.resources.length;
        return Promise.all(manifest.resources.map(function (name) {
          return fetch('game/' + name)
            .then(function (response) {
              if (!response.ok) throw new Error('game/' + name + ' (' + response.status + ')');
              return response.arrayBuffer();
            })
            .then(function (buffer) {
              FS.writeFile('/' + name, new Uint8Array(buffer));
              done += 1;
              say('Loading the game files… ' + done + '/' + total);
              return null;
            });
        }));
      })
      .then(function () {
        removeRunDependency('freegemas-files');
      })
      .catch(function (problem) {
        fail('The game files could not be loaded: ' + problem.message);
      });
  }],
  postRun: [function () {
    if (failed) return;
    running = true;
    boot.hidden = true;
    keepTitle();
    canvas.focus({ preventScroll: true });
    say('Running. Click the game, then use the mouse or arrow keys.');
    playBtn.textContent = 'Running';
    soundBtn.disabled = false;
    fullscreenBtn.disabled = !document.getElementById('screen').requestFullscreen;
    restartBtn.disabled = false;
    enableSound(true);   /* best effort: a click just happened */
  }],
  print: function (text) { console.log(text); },
  printErr: function (text) { console.warn(text); },
  setStatus: function (text) {
    if (text && !running && !failed) say(text);
  },
  onAbort: function () { fail('The emulator stopped unexpectedly.'); }
};

/* X16 audio comes from the emulator's SDL2 audio context; browsers keep it
 * suspended until a user gesture, so the button only says "Sound on" once the
 * context is actually running. `j2c_start_audio` is the official build's hook. */
function enableSound(on) {
  var called = false;
  try {
    Module.ccall('j2c_start_audio', 'void', ['bool'], [on]);
    called = true;
  } catch (ignored) {
    called = false;
  }
  var context = Module.SDL2 && Module.SDL2.audioContext;
  function settle(state) {
    soundOn = state;
    soundBtn.textContent = state ? 'Sound on' : 'Sound off';
    soundBtn.setAttribute('aria-pressed', state ? 'true' : 'false');
  }
  if (!called) { settle(false); return; }
  if (!on) {
    if (context && context.state === 'running') context.suspend().catch(function () {});
    settle(false);
    return;
  }
  if (!context) { settle(true); return; }
  if (context.state === 'running') { settle(true); return; }
  context.resume().then(function () { settle(true); }, function () { settle(false); });
}

function start() {
  if (started) return;
  started = true;
  playBtn.disabled = true;
  if (typeof WebAssembly === 'undefined') {
    fail('This browser does not support WebAssembly.');
    return;
  }
  say('Loading the emulator…');
  var script = document.createElement('script');
  script.src = 'emulator/x16emu.js';
  script.onerror = function () { fail('The emulator could not be downloaded.'); };
  document.body.append(script);
}

playBtn.addEventListener('click', start);

canvas.addEventListener('click', function () { canvas.focus({ preventScroll: true }); });
canvas.addEventListener('keydown', function (event) {
  if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', ' ', 'Backspace'].indexOf(event.key) >= 0) {
    event.preventDefault();
  }
});
canvas.addEventListener('contextmenu', function (event) { event.preventDefault(); });
canvas.addEventListener('mousedown', function () { canvas.focus({ preventScroll: true }); });
canvas.addEventListener('webglcontextlost', function (event) {
  event.preventDefault();
  fail('The browser lost its WebGL context.');
});

soundBtn.addEventListener('click', function () {
  enableSound(!soundOn);
  canvas.focus({ preventScroll: true });
});

fullscreenBtn.addEventListener('click', function () {
  var screen = document.getElementById('screen');
  if (document.fullscreenElement) {
    document.exitFullscreen().catch(function () {});
  } else if (screen.requestFullscreen) {
    screen.requestFullscreen().catch(function () { say('Fullscreen is unavailable here.'); });
  }
  canvas.focus({ preventScroll: true });
});

restartBtn.addEventListener('click', function () { location.reload(); });

/* The emulator shell renames the document while it boots; keep our title. */
var pageTitle = 'Freegemas — Commander X16';
function keepTitle() {
  if (document.title !== pageTitle) document.title = pageTitle;
}
document.title = pageTitle;
setInterval(keepTitle, 1000);

/* Keyboard focus is required for the KERNAL to see keys. */
window.addEventListener('load', function () { canvas.focus({ preventScroll: true }); });

if (autoStart) start();
