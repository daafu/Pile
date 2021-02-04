using System;
using System.Collections;
using System.Diagnostics;
using System.Threading;
using System.IO;

using internal Pile;

/* DEFINES:
 * PILE_LONG_LOG_RECORD - increases amount of output log lines Log remembers from 64 to 512
 * PILE_DISABLE_LOG_MESSAGES - adds [SkipCall] attribute to Log.Message functions
 * PILE_DISABLE_LOG_WARNINGS - adds [SkipCall] attribute to Log.Warning functions
 * PILE_DISABLE_PACKAGER - removes package building functionality from EntryPoint
 * PILE_DISABLE_AUTOMATIC_PACKAGE_RELOAD - disables automatic DEBUG package hot reload check when focusing window
 */

namespace Pile
{
	[Optimize]
	public static class Core
	{
		static this()
		{
			Title = new .();
		}

		static ~this()
		{
			if (run) Delete();

			delete Title;
		}

		static void Delete()
		{
			// Delete assets and textures while modules are still present
			delete Assets;

			delete Window;
			delete Input;

			delete Audio;
			delete Graphics;
			delete System;
		}

		// Used for Log/info only (to better trace back/ignore issues and bugs base on error logs).
		// '.Minor' should be incremented for changes incompatible with older versions.
		// '.Major' is incremented at milestones or big changes.
		static readonly Version Version = .(1, 0);

		internal static bool run;
		static bool exiting;

		public static String Title { get; private set; }

		public static System System { get; private set; }
		public static Graphics Graphics { get; private set; }
		public static Audio Audio { get; private set; }

		public static Input Input { get; private set; }
		public static Window Window { get; private set; }

		public static Assets Assets { get; private set; }

		static Game Game;

		public static Result<void> Run(uint32 windowWidth, uint32 windowHeight, Game game, StringView gameTitle, bool deleteGameOnShutdown = true)
		{
			Debug.Assert(!run, "Core was already run");
			Debug.Assert(game != null, "Game cannot be null");

			run = true;
#if DEBUG
			Console.WriteLine();
#endif
			Log.Info(scope $"Initializing Pile {Version.Major}.{Version.Minor}");
			var w = scope Stopwatch(true);
			Title.Set(gameTitle);
			System = new System();
			Graphics = new Graphics();
			Audio = new Audio();

			// Print platform
			{
				let s = scope String();
				Environment.OSVersion.ToString(s);

				Log.Info(scope $"Platform: {s} (bfp: {Environment.OSVersion.Platform})");
			}

			// System init
			{
				System.Initialize();
				
				System.DetermineDataPaths(Title);
				Directory.SetCurrentDirectory(System.DataPath);

				Window = new Window(gameTitle, windowWidth, windowHeight);
				Input = new Input();

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

			// Assets init
			Assets = new Assets();

			// Log init
			Log.Initialize();

			w.Stop();
			Log.Info(scope $"Pile initialized (took {w.Elapsed.Milliseconds}ms)");

			// Prepare for running game
			Game = game;

			let timer = scope Stopwatch(true);
			var frameCount = 0;
			var lastCounted = 0L;

			int64 lastTime = 0;
			int64 currTime;
			int64 diffTime;

			// Startup game
			Game.[Friend]Startup();

			while(!exiting)
			{
				// Step time and diff
				if (Time.maxTicks == Time.targetTicks)
				{
					// Still calculate actual fps
					currTime = timer.[Friend]GetElapsedDateTimeTicks();

					diffTime = Time.targetTicks;
				}
				else
				{
					currTime = timer.[Friend]GetElapsedDateTimeTicks();
					
					diffTime = Math.Min(Time.maxTicks, currTime - lastTime);
					lastTime = currTime;
				}

				// Raw time
				Time.RawDuration += diffTime;
				Time.RawDelta = (float)(diffTime * TimeSpan.[Friend]SecondsPerTick);

				// Update core modules
				Graphics.Step();
				Input.Step();
				System.Step();

				if (Time.freeze > float.Epsilon)
				{
					// Freeze time
					Time.freeze -= Time.RawDelta;

					Time.Delta = 0;
					Game.[Friend]Step();

					if (Time.freeze <= float.Epsilon)
						Time.freeze = 0;
				}
				else
				{
					// Scaled time
					Time.Duration += Time.Scale == 1 ? diffTime : (int64)Math.Round(diffTime * Time.Scale);
					Time.Delta = Time.RawDelta * Time.Scale;
	
					// Update game
					Game.[Friend]Step();
					Game.[Friend]Update();
				}
				Audio.AfterUpdate();

				// Render
				if (!exiting && !Window.Closed)
				{
					Window.Render(); // Calls CallRender()
					Window.Present();
				}

				// Count FPS
				frameCount++;
				if ((float)(timer.[Friend]GetElapsedDateTimeTicks() - lastCounted) / TimeSpan.TicksPerSecond >= 1)
				{
					Time.FPS = frameCount;
					lastCounted = timer.[Friend]GetElapsedDateTimeTicks();
					frameCount = 0;
				}

				// Wait for FPS
				if (timer.[Friend]GetElapsedDateTimeTicks() - currTime < Time.targetTicks && !exiting)
				{
					let sleep = Time.targetTicks - (timer.[Friend]GetElapsedDateTimeTicks() - currTime);
					
					if (sleep > 0)
						Thread.Sleep((int32)((float)sleep / TimeSpan.TicksPerMillisecond));
				}
			}

			// Shutdown game
			Game.[Friend]Shutdown();

			if (deleteGameOnShutdown) delete Game;
			return .Ok;
		}

		public static void Exit()
		{
			if (run && !exiting)
			{
				exiting = true;
			}
		}

		internal static void CallRender()
		{
			Game.[Friend]Render();
			Graphics.AfterRender();
		}

		[NoReturn]
		/// Like Runtime.FatalError(), but also logs the error (which, depending on Log configuration also saves the log file)
		public static void FatalError(String msg = "Fatal error encountered", String filePath = Compiler.CallerFilePath, int line = Compiler.CallerLineNum)
		{
			String failStr = scope .()..AppendF("{} at line {} in {}", msg, line, filePath);
			Log.Error(failStr);
			Internal.FatalError(failStr, 1);
		}

		/// Like Runtime.Assert(), but also logs the error (which, depending on Log configuration also saves the log file)
		public static void Assert(bool condition, String error = Compiler.CallerExpression[0], String filePath = Compiler.CallerFilePath, int line = Compiler.CallerLineNum) 
		{
			if (!condition)
			{
				String failStr = scope .()..AppendF("Assert failed: {} at line {} in {}", error, line, filePath);
				Log.Error(failStr);
				Internal.FatalError(failStr, 1);
			}
		}
	}
}
