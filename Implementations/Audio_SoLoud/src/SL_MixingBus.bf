using internal Pile;

namespace Pile.Implementations
{
	public class SL_MixingBus : MixingBus.Platform
	{
		public override bool IsMasterBus => false;

		internal this() {}

		public override void Initialize(MixingBus bus)
		{

		}

		public override void SetVolume(float volume)
		{

		}

		public override void AddBus(MixingBus bus)
		{

		}

		public override void RemoveBus(MixingBus bus)
		{

		}

		public override void AddSource(AudioSource source)
		{

		}

		public override void RemoveSource(AudioSource source)
		{

		}
	}
}
