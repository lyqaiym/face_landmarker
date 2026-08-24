package com.google.mediapipe.framework.image;

final class AutoValue_MPImageProperties extends $AutoValue_MPImageProperties {
  private transient volatile int hashCode;

  private transient volatile boolean hashCode$Memoized;

  AutoValue_MPImageProperties(int imageFormat$, int storageType$) {
    super(imageFormat$, storageType$);
  }

  @Override
  public int hashCode() {
    if (!hashCode$Memoized) {
      synchronized (this) {
        if (!hashCode$Memoized) {
          hashCode = super.hashCode();
          hashCode$Memoized = true;
        }
      }
    }
    return hashCode;
  }

  @Override
  public boolean equals(Object that) {
    if (this == that) {
      return true;
    }
    return that instanceof AutoValue_MPImageProperties && this.hashCode() == that.hashCode() && super.equals(that);
  }
}
