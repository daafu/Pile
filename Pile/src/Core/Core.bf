using System;
using System.Diagnostics;
using System.Threading;
using System.IO;

using internal Pile;

namespace Pile
{
	/* Preprocessor defines:
		PILE_FORCE_DEBUG_TOOLS
		PILE_FORCE_ASSET_TOOLS
	*/

	struct RunConfig
	{
		public WindowState windowState;
		public uint32 windowWidth = 1280;
		public uint32 windowHeight = 720;
		public StringView gameTitle;
		public StringView windowTitle;
		public function Game() createGame;
	}

	[Optimize,StaticInitPriority(PILE_SINIT_ENTRY)]
	static class Core
	{
		public static Event<delegate Result<void>()> OnStart ~ OnStart.Dispose();
		public static RunConfig Config = .();

		public static String[] CommandLine;

		static int Main(String[] args)
		{
			// Store args
			CommandLine = args;

			// Packager mode
			if (args.Count > 0 && args[0] == "-packager")
			{
				if (Packager.BuildAndPackageAssets() case .Err)
					Runtime.FatalError("Error while running packager");
				return 0;
			}

#if DEBUG
			// In debug, run this on actual execute for debugging perks
			Packager.BuildAndPackageAssets().IgnoreError();
#endif
			
			// Run onStart
			if (OnStart.HasListeners)
			{
				Runtime.Assert(OnStart() case .Ok, "Error in OnStart");
				OnStart.Dispose();
			}
			
			// Run with registered settings
			Run(Config);

			return 0;
		}

		public static class Defaults
		{
			public static bool TexturesGenMipmaps = true;
			public static bool SpriteFontsGenMipmaps = true;
			public static TextureFilter TextureFilter = .Linear;
			public static TextureFilter SpriteFontFilter = .Linear;

			public static void SetupPixelPerfect(bool pixelFonts = false)
			{
				TexturesGenMipmaps = false;
				TextureFilter = .Nearest;

				if (pixelFonts)
				{
					SpriteFontsGenMipmaps = false;
					SpriteFontFilter = .Linear;
				}
			}
		}

		// Used for Log/info only (to better trace back/ignore issues and bugs base on error logs).
		// '.Minor' should be incremented for changes incompatible with older versions.
		// '.Major' is incremented at milestones or big changes.
		public static readonly Version Version = .(3, 0);

		internal static bool run;
		static bool exiting;
		static uint forceSleepMS;
		static bool skipRender;

		// This is interchangeable.. if you really need to
		internal static function void() coreLoop = => DoCoreLoop;

		internal static Event<Action> OnInit = .() ~ _.Dispose();
		internal static Event<Action> OnDestroy = .() ~ _.Dispose();
		internal static Event<Action> OnSwap = .() ~ _.Dispose();

		static String title = new .() ~ delete _;
		static Game game;
		static Game swapGame;

		[Inline]
		public static Game Game => game;

		[Inline]
		public static StringView Title => title;

		internal static void Run(RunConfig config)
		{
			Debug.Assert(!run, "Core was already run");
			Debug.Assert(config.gameTitle.Ptr != null, "Core.Config.gameTitle has to be set. Provide an unchanging, file system safe string literal");
			Debug.Assert(config.createGame != null, "Core.Config.createGame has to be set. Provide a function that returns an instance of your game");

			run = true;

			Log.Info(scope $"Initializing Pile {Version.Major}.{Version.Minor}");
			var w = scope Stopwatch(true);
			title.Set(config.gameTitle);

			// Print platform
			{
				let s = scope String();
				Environment.OSVersion.ToString(s);

				Log.Info(scope $"Platform: {s} (bfp: {Environment.OSVersion.Platform})");
			}

			// System init
			{
				System.Initialize();
				
				System.DetermineDataPaths(title);
				Directory.SetCurrentDirectory(System.DataPath);

				System.window = new Window(config.windowTitle.Ptr == null ? config.gameTitle : config.windowTitle, config.windowWidth, config.windowHeight, config.windowState, true);
				Input.Initialize();

				Log.Info(scope $"System: {System.ApiName} {System.MajorVersion}.{System.MinorVersion} ({System.Info})");
			}

			// Graphics init
			{
				Graphics.Initialize();
				Log.Info(scope $"Graphics: {Graphics.ApiName} {Graphics.MajorVersion}.{Graphics.MinorVersion} ({Graphics.Info})");
			}

			// Audio init
			{
				Audio.Initialize();
				Log.Info(scope $"Audio: {Audio.ApiName} {Audio.MajorVersion}.{Audio.MinorVersion} ({Audio.Info})");
			}

			Log.CreateDefaultPath(); // Relies on System.UserPath being set

			BeefPlatform.Initialize();
			Perf.Initialize();
			Assets.Initialize();

			w.Stop();
			Log.Info(scope $"Pile initialized (took {w.Elapsed.Milliseconds}ms)");

			// First step, prepare for example Input info for startup call
			PileStep!();

			if (OnInit.HasListeners)
				OnInit();

			// Prepare for running game
			game = config.createGame();
			Debug.AssertNotStack(game);
			Debug.Assert(game != null, "Game cannot be null");
			game.[Friend]Startup();

			System.Window.Visible = true;

			coreLoop();

			// Shutdown game
			game.[Friend]Shutdown();

			// Destroy
			delete game;

			if (OnDestroy.HasListeners)
				OnDestroy();

			// Destroy things that are only set when Pile was actually run.
			// Since Pile isn't necessarily run (Tests, packager) things that
			// are created in static initialization should be deleted in static
			// destruction, and things from Initialize() in Destroy() or Delete()
			Assets.Destroy();

			Audio.Destroy();
			Graphics.Destroy();

			Input.Destroy();
			System.Delete();
			System.Destroy();

			run = false;
		}

		internal static mixin PileStep()
		{
			Graphics.Step();
			System.Step();
			Input.Step();
		}

		internal static void DoCoreLoop()
		{
			let timer = scope Stopwatch(true);
			var frameCount = 0;
			var lastCounted = 0L;

			int64 lastTime = 0;
			int64 currTime;
			int64 diffTime;

			while(!exiting)
			{
				currTime = timer.[Friend]GetElapsedDateTimeTicks();

				// Step time and diff
				if (!Time.forceFixed)
				{
					diffTime = Math.Min(Time.maxTicks, currTime - lastTime);
					lastTime = currTime;
				}
				else
				{
					// Force diffTime and therefore deltas regardless of actual performance
					diffTime = Time.targetTicks;
				}
				
				{
					PerfTrack("Pile.Core.DoCoreLoop:Update");

					// Raw time
					Time.rawDuration += diffTime;
					Time.rawDelta = (float)(diffTime * TimeSpan.[Friend]SecondsPerTick);
					
					Perf.Step();

					// Update core modules
					PileStep!();

					if (swapGame != null)
					{
						game.[Friend]Shutdown();
						delete game;

						game = swapGame;
						swapGame = null;
						game.[Friend]Startup();

						if (OnSwap.HasListeners)
							OnSwap();
					}

					if (!Time.freezing)
					{
						// Scaled time
						Time.duration += Time.Scale == 1 ? diffTime : (int64)Math.Round(diffTime * Time.Scale);
						Time.delta = Time.rawDelta * Time.Scale;

						// Update game
						game.[Friend]Step();
						game.[Friend]Update();
					}
					else
					{
						// Freeze time
						Time.freeze -= Time.rawDelta;

						Time.delta = 0;
						game.[Friend]Step();

						if (Time.freeze <= float.Epsilon)
						{
							Time.freeze = 0;
							Time.freezing = false;
						}
					}
					Audio.AfterUpdate();
				}

				// Render
				if (!skipRender && !exiting && !System.window.Closed)
				{
					{
						PerfTrack("Pile.Core.DoCoreLoop:Render");

						System.window.Render(); // Calls WindowRender()
					}

					{
						PerfTrack("Pile.Core.DoCoreLoop:Present");

						let vsVal = System.window.VSync;
						if (vsVal && timer.[Friend]GetElapsedDateTimeTicks() - currTime >= Time.targetTicks)
							System.window.VSync = false;

						System.window.Present();

						if (vsVal)
							System.window.VSync = true;
					}
				}

				// Record FPS
				frameCount++;
				let endCurrTime = timer.[Friend]GetElapsedDateTimeTicks();
				const int fpsReportInterval = TimeSpan.TicksPerSecond / 4;
				const int fpsReportMult = TimeSpan.TicksPerSecond / fpsReportInterval;
				if (endCurrTime - lastCounted >= fpsReportInterval)
				{
					// Extrapolate back to per second instead of per reportInterval
					Time.fps = frameCount * fpsReportMult;
					lastCounted = endCurrTime;
					frameCount = 0;
				}

				// Record loop ticks (delta without sleep)
				Time.loopTicks = endCurrTime - currTime;
#if DEBUG || PILE_FORCE_DEBUG_TOOLS
				// We already have a timer running here...
				Perf.[Friend]EndSection("Pile.Core.DoCoreLoop (no sleep)", TimeSpan(Time.loopTicks));
#endif

				// Wait for FPS
				if (endCurrTime - currTime < Time.targetTicks && !exiting)
				{
					let sleep = Time.targetTicks - (timer.[Friend]GetElapsedDateTimeTicks() - currTime);

					var worstSleepError = 0;
					var lastSleep = 0;
					let sleepWatch = scope Stopwatch()..Start();
					while (lastSleep < sleep - worstSleepError)
					{
						Thread.Sleep(1);
						let now = sleepWatch.[Friend]GetElapsedDateTimeTicks();
						let actualSleepTime = now - lastSleep;
						lastSleep = now;

						let sleepError = actualSleepTime - TimeSpan.TicksPerMillisecond;
						if (worstSleepError < sleepError)
							worstSleepError = sleepError;
					}

					while (sleepWatch.[Friend]GetElapsedDateTimeTicks() < sleep)
						Thread.SpinWait(1);
				}

				// Force sleep
				if (forceSleepMS != 0)
				{
					timer.Stop();
					Thread.Sleep((int32)forceSleepMS);
					forceSleepMS = 0;
					timer.Start();
				}
			}
		}

		public static void Exit()
		{
			if (run && !exiting)
			{
				exiting = true;
			}
		}

		[Inline]
		public static void SkipRender()
		{
			skipRender = true;
		}

		[Inline]
		public static void Sleep(uint ms)
		{
			forceSleepMS = ms;
		}

		/// Swaps the current game out for a new one. There is no internal reset when
		/// swapping. The previous game is responsible for its cleanup.
		/// This is probably only sometimes appropriate to use, like for example
		/// for editor environments and alike.
		public static void SwapGame(Game newGame)
		{
			Debug.AssertNotStack(newGame);
			Debug.Assert(newGame != null);
			Runtime.Assert(swapGame == null, "Can only swap games once a frame!");

			swapGame = newGame;
		}

		[Inline]
		internal static void WindowRender()
		{
			game.[Friend]Render();
			Graphics.AfterRender();
		}
	}
}
