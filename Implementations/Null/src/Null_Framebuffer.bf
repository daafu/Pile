using System;

using internal Pile;

namespace Pile.Implementations
{
	public class Null_Framebuffer : FrameBuffer.Platform
	{
		[SkipCall]
		protected internal override void ResizeAndClear(uint32 width, uint32 height) {}
	}
}
