namespace ParentalControl.Windows.Core;

public sealed class ReplayProtector
{
    private readonly object gate = new();
    private readonly HashSet<Guid> recentIds = [];
    private readonly Queue<Guid> insertionOrder = new();
    private ulong highestSequence;

    public ReplayProtector(ulong initialSequence = 0)
    {
        highestSequence = initialSequence;
    }

    public ulong HighestSequence
    {
        get
        {
            lock (gate)
            {
                return highestSequence;
            }
        }
    }

    public void Accept(ProtocolEnvelope envelope)
    {
        lock (gate)
        {
            if (envelope.Sequence <= highestSequence || !recentIds.Add(envelope.Id))
            {
                throw new InvalidDataException("The protocol message was replayed or reordered.");
            }

            highestSequence = envelope.Sequence;
            insertionOrder.Enqueue(envelope.Id);
            while (insertionOrder.Count > 256)
            {
                recentIds.Remove(insertionOrder.Dequeue());
            }
        }
    }
}
