import { useEffect, useRef, type RefObject } from 'react';

/**
 * Hook to make a target element draggable by dragging a handle element.
 * Updates target.style.transform to translate the element smoothly.
 * Resets translation back to center whenever the serial identifier changes.
 */
export function useDraggable(
  targetRef: RefObject<HTMLElement | null>,
  handleRef: RefObject<HTMLElement | null>,
  serial: string | null | undefined
) {
  const posRef = useRef({ x: 0, y: 0 });

  // Reset position when serial changes (e.g. modal closed and reopened)
  useEffect(() => {
    posRef.current = { x: 0, y: 0 };
    const target = targetRef.current;
    if (target) {
      target.style.transform = '';
    }
  }, [serial, targetRef]);

  useEffect(() => {
    if (!serial) return;
    const target = targetRef.current;
    const handle = handleRef.current;
    if (!target || !handle) return;

    let startX = 0;
    let startY = 0;
    let initialX = 0;
    let initialY = 0;

    const onPointerDown = (e: PointerEvent) => {
      // Don't drag if clicking interactive elements inside the handle
      const targetElement = e.target as HTMLElement;
      const targetTag = targetElement.tagName;
      if (
        targetTag === 'BUTTON' ||
        targetTag === 'INPUT' ||
        targetTag === 'A' ||
        targetElement.closest('.ios-mode-toggle') ||
        targetElement.closest('button') ||
        targetElement.closest('.modal-close')
      ) {
        return;
      }
      
      e.preventDefault();
      startX = e.clientX;
      startY = e.clientY;
      initialX = posRef.current.x;
      initialY = posRef.current.y;

      document.addEventListener('pointermove', onPointerMove);
      document.addEventListener('pointerup', onPointerUp);
    };

    const onPointerMove = (e: PointerEvent) => {
      const dx = e.clientX - startX;
      const dy = e.clientY - startY;
      
      const newX = initialX + dx;
      const newY = initialY + dy;
      
      posRef.current = { x: newX, y: newY };
      target.style.transform = `translate(${newX}px, ${newY}px)`;
    };

    const onPointerUp = () => {
      document.removeEventListener('pointermove', onPointerMove);
      document.removeEventListener('pointerup', onPointerUp);
    };

    handle.addEventListener('pointerdown', onPointerDown);
    handle.style.cursor = 'move';
    handle.title = 'Drag to move panel';

    return () => {
      handle.removeEventListener('pointerdown', onPointerDown);
      document.removeEventListener('pointermove', onPointerMove);
      document.removeEventListener('pointerup', onPointerUp);
    };
  }, [serial, targetRef, handleRef]);
}
