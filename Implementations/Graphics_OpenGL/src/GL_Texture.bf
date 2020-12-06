using System;
using OpenGL43;

using internal Pile;

namespace Pile.Implementations
{
	public class GL_Texture : Texture.Platform
	{
		internal uint32 textureID;

		readonly GL_Graphics graphics;
		internal bool isFrameBuffer;

		uint glInternalFormat;
		uint glFormat;
		uint glType;

		uint32 currWidth;
		uint32 currHeight;

		internal this(GL_Graphics graphics, uint32 width, uint32 height, TextureFormat format)
		{
			this.graphics = graphics;

			switch (format)
			{
			case .R: glInternalFormat = glFormat = GL.GL_RED;
			case .RG: glInternalFormat = glFormat = GL.GL_RG;
			case .RGB: glInternalFormat = glFormat = GL.GL_RGB;
			case .Color: glInternalFormat = glFormat = GL.GL_RGBA;
			case .DepthStencil:
				glInternalFormat = GL.GL_DEPTH24_STENCIL8;
				glFormat = GL.GL_DEPTH_STENCIL;
			}

			switch (format)
			{
			case .R, .RG, .RGB, .Color: glType = GL.GL_UNSIGNED_BYTE;
			case .DepthStencil: glType = GL.GL_UNSIGNED_INT_24_8;
			}

			// GL create texture
			Create(width, height, Texture.DefaultTextureFilter, default, default); // Defaults for values we dont know/can be set yet
		}

		public ~this()
		{
			Delete();
		}

		void Delete()
		{
			if (textureID != 0)
			{
				graphics.texturesToDelete.Add(textureID);
				textureID = 0;
			}
		}

		private void Create(uint32 width, uint32 height, TextureFilter filter, TextureWrap wrapX, TextureWrap wrapY)
		{
			currWidth = width;
			currHeight = height;

			GL.glGenTextures(1, &textureID);
			Prepare();

			// TODO: optional mipmaps?
			GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, (int)glInternalFormat, width, height, 0, glFormat, glType, null);
			int glTexFilter = (int)(filter == .Nearest ? GL.GL_NEAREST : GL.GL_LINEAR);
			int glTexWrapX = (int)(wrapX == .Clamp ? GL.GL_CLAMP_TO_EDGE : GL.GL_REPEAT);
			int glTexWrapY = (int)(wrapY == .Clamp ? GL.GL_CLAMP_TO_EDGE : GL.GL_REPEAT);
			GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, glTexFilter);
			GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, glTexFilter);
			GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_S, glTexWrapX);
			GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_T, glTexWrapY);

			GL.glBindTexture(GL.GL_TEXTURE_2D, 0);
		}

		void Prepare()
		{
			GL.glActiveTexture(GL.GL_TEXTURE0);
			GL.glBindTexture(GL.GL_TEXTURE_2D, textureID);
		}

		internal override void ResizeAndClear(uint32 width, uint32 height, TextureFilter filter, TextureWrap wrapX, TextureWrap wrapY)
		{
			Delete();
			Create(width, height, filter, wrapX, wrapY);
		}

		internal override void SetFilter(TextureFilter filter)
		{
			Prepare();
			int glTexFilter = filter == .Nearest ? GL.GL_NEAREST : GL.GL_LINEAR;
			GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, glTexFilter);
			GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, glTexFilter);

			GL.glBindTexture(GL.GL_TEXTURE_2D, 0);

		}

		internal override void SetWrap(TextureWrap x, TextureWrap y)
		{
			Prepare();
			int glTexWrapX = (int)(x == .Clamp ? GL.GL_CLAMP_TO_EDGE : GL.GL_REPEAT);
			int glTexWrapY = (int)(y == .Clamp ? GL.GL_CLAMP_TO_EDGE : GL.GL_REPEAT);
			GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_S, glTexWrapX);
			GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_T, glTexWrapY);

			GL.glBindTexture(GL.GL_TEXTURE_2D, 0);
		}

		internal override void SetData(void* buffer)
		{
			Prepare();
			GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, (int)glInternalFormat, currWidth, currHeight, 0, glFormat, glType, buffer);

			GL.glBindTexture(GL.GL_TEXTURE_2D, 0);
		}

		internal override void GetData(void* buffer)
		{
			Prepare();
			GL.glGetTexImage(GL.GL_TEXTURE_2D, 0, glInternalFormat, glType, buffer);

			GL.glBindTexture(GL.GL_TEXTURE_2D, 0);
		}

		internal override bool IsFrameBuffer() => isFrameBuffer;
	}
}
