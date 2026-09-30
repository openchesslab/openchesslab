import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";

const COLORS = ["yellow", "blue", "red", "orange", "purple"];

const Board = {
  mounted() {
    this.drag = null;
    this.dragGhost = null;
    this.drawing = null;
    this.arrowStart = null;
    this.suppressClick = false;
    this.pendingMoves = [];
    this.specSelect = null;
    this.pendingShapes = [];
    this.longPress = null;

    // Mobile app shell: the board fills the space left by the chrome, so it
    // scales with the viewport and the panel size.
    this.fitBoard = () => {
      const zone = this.el.closest("[data-board-zone]");
      if (!zone || !window.matchMedia("(max-width: 859.98px)").matches) {
        this.el.style.width = "";
        this.el.style.height = "";
        return;
      }
      const size = Math.floor(Math.min(zone.clientWidth, zone.clientHeight));
      if (size > 0) {
        this.el.style.width = `${size}px`;
        this.el.style.height = `${size}px`;
      }
    };

    const boardZone = this.el.closest("[data-board-zone]");
    if (boardZone) {
      this.boardFitObserver = new ResizeObserver(this.fitBoard);
      this.boardFitObserver.observe(boardZone);
      this.fitBoard();
      requestAnimationFrame(() => this.fitBoard());
      window.addEventListener("resize", this.fitBoard);
    }

    this.pointerDown = (event) => {
      const square = this.squareAt(event.target);
      if (square === null) return;

      this.arrowStart = null;
      this.removeDrawingPreview();

      if (event.button === 2) {
        event.preventDefault();
        const color = this.annotationColor(event);
        this.drawing = {
          from: square,
          color,
          x: event.clientX,
          y: event.clientY,
          moved: false,
        };
        return;
      }

      if (event.button !== 0) return;

      if (event.pointerType !== "mouse") {
        this.beginLongPress(square, event);
      }

      if (!event.target.closest("[data-piece]")) return;
      this.drag = {
        from: square,
        x: event.clientX,
        y: event.clientY,
        moved: false,
      };
    };

    this.pointerMove = (event) => {
      if (this.longPress) {
        const travelled =
          Math.abs(event.clientX - this.longPress.x) +
          Math.abs(event.clientY - this.longPress.y);
        if (travelled > 10) this.cancelLongPress();
      }

      if (this.drawing) {
        if (
          !this.drawing.moved &&
          Math.abs(event.clientX - this.drawing.x) +
            Math.abs(event.clientY - this.drawing.y) >
            6
        ) {
          this.drawing.moved = true;
          this.el.setPointerCapture?.(event.pointerId);
        }
        if (this.drawing.moved)
          this.renderDrawingPreview(event.clientX, event.clientY);
        return;
      }

      if (!this.drag) return;
      if (
        !this.drag.moved &&
        Math.abs(event.clientX - this.drag.x) +
          Math.abs(event.clientY - this.drag.y) >
          6
      ) {
        this.drag.moved = true;
        this.cancelLongPress();
        this.el.dataset.dragging = "true";
        this.el.setPointerCapture?.(event.pointerId);
        this.startDragPreview(this.drag.from, event.clientX, event.clientY);
      }
      if (this.drag.moved) this.renderDragPreview(event.clientX, event.clientY);
    };

    this.pointerUp = (event) => {
      this.cancelLongPress();
      const target = document.elementFromPoint(event.clientX, event.clientY);
      const square = this.squareAt(target);

      if (this.drawing) {
        const { from, color } = this.drawing;
        this.drawing = null;
        if (square === from) {
          this.pushAnnotation({ type: "square", square, color });
        } else if (square !== null) {
          this.pushAnnotation({ type: "arrow", from, to: square, color });
        }
        this.removeDrawingPreview();
        return;
      }

      if (!this.drag) return;
      const { from, moved } = this.drag;
      this.drag = null;
      delete this.el.dataset.dragging;
      if (moved && square !== null && square !== from) {
        this.suppressClick = true;
        window.setTimeout(() => {
          this.suppressClick = false;
        }, 0);
        this.playMove("board-move", { from, to: square }, from, square, {
          reuseDragGhost: true,
        });
      } else {
        this.clearDragPreview(from);
      }
    };

    this.suppressDraggedClick = (event) => {
      if (!this.suppressClick) return;
      event.preventDefault();
      event.stopPropagation();
      this.suppressClick = false;
    };

    this.pointerCancel = () => {
      this.cancelLongPress();
      this.clearDragPreview(this.drag?.from);
      this.drag = null;
      this.drawing = null;
      this.arrowStart = null;
      this.removeDrawingPreview();
      delete this.el.dataset.dragging;
    };

    this.keyDown = (event) => {
      if (event.key === "Escape") {
        if (this.arrowStart !== null || this.drawing) {
          this.cancelArrow();
          return;
        }
        this.specSelect = null;
        this.markSpecSelect(null);
        this.clearPendingShapes();
        this.pushEvent("clear-annotations", {});
        return;
      }

      if (/^[1-5]$/.test(event.key)) {
        this.pushEvent("annotation-color", {
          color: COLORS[Number(event.key) - 1],
        });
        return;
      }

      if (event.key.toLowerCase() === "c") {
        this.clearPendingShapes();
        this.pushEvent("clear-annotations", {});
        return;
      }

      const button = event.target.closest("[data-square]");
      if (!button) return;
      const current = Number(button.dataset.square);

      if (event.key.toLowerCase() === "h") {
        event.preventDefault();
        this.pushAnnotation({
          type: "square",
          square: current,
          color: this.el.dataset.annotationColor || "blue",
        });
        return;
      }

      if (event.key.toLowerCase() === "a") {
        event.preventDefault();
        this.toggleArrow(current);
        return;
      }

      if (
        this.arrowStart !== null &&
        (event.key === "Enter" || event.key === " ")
      ) {
        event.preventDefault();
        this.finishArrow(current);
        return;
      }

      // Shift+arrows step the mainline (handled at the document level)
      if (event.shiftKey) return;

      const offsets = {
        ArrowLeft: this.el.dataset.orientation === "black" ? 1 : -1,
        ArrowRight: this.el.dataset.orientation === "black" ? -1 : 1,
        ArrowUp: this.el.dataset.orientation === "black" ? -8 : 8,
        ArrowDown: this.el.dataset.orientation === "black" ? 8 : -8,
      };
      const offset = offsets[event.key];
      if (offset === undefined) return;
      event.preventDefault();
      const file = current % 8;
      const rank = Math.floor(current / 8);
      const nextFile = file + (offset === -1 || offset === 1 ? offset : 0);
      const nextRank = rank + (offset === -8 || offset === 8 ? offset / 8 : 0);
      if (nextFile < 0 || nextFile > 7 || nextRank < 0 || nextRank > 7) return;
      const next = nextRank * 8 + nextFile;
      this.el.querySelector(`[data-square="${next}"]`)?.focus();
      this.pushEvent("board-cursor", { square: next });
      if (this.arrowStart !== null) {
        requestAnimationFrame(() => this.renderKeyboardArrowPreview());
      }
    };

    // Click-to-move: the source click is remembered locally (with the
    // speculative side to move), so the target click can play optimistically
    // while the previous move's cross-region round trip is still in flight.
    // The server still selects and validates in event order; the optimistic
    // hold rolls back when the server does not play the move.
    this.squareClick = (event) => {
      if (this.suppressClick) return;
      if (!this.playMode()) return;
      const squareEl = event.target.closest("[data-square]");
      if (!squareEl || !this.el.contains(squareEl)) return;
      const square = Number(squareEl.dataset.square);

      if (this.specSelect !== null && this.specSelect !== square) {
        // Target click: the hook owns the event so the square's own
        // phx-click does not double-send the same board-square event.
        event.stopPropagation();
        const from = this.specSelect;
        this.specSelect = null;
        this.markSpecSelect(null);
        this.playMove("board-square", { square: String(square) }, from, square);
        return;
      }

      // Source click (or deselect): remember it locally. The square's
      // phx-click still fires so the server selects authoritatively and
      // renders the legal targets.
      this.specSelect =
        square === this.specSelect ? null : this.selectableSpecPiece(square);
      this.markSpecSelect(this.specSelect);
    };
    this.el.addEventListener("click", this.squareClick, true);

    this.clearPending = () => this.clearPendingShapes();
    document.addEventListener("openchesslab:clear-annotations", this.clearPending);

    this.contextMenu = (event) => event.preventDefault();
    this.el.addEventListener("pointerdown", this.pointerDown);
    this.el.addEventListener("pointermove", this.pointerMove);
    this.el.addEventListener("pointerup", this.pointerUp);
    this.el.addEventListener("pointercancel", this.pointerCancel);
    this.el.addEventListener("click", this.suppressDraggedClick, true);
    this.el.addEventListener("keydown", this.keyDown);
    this.el.addEventListener("contextmenu", this.contextMenu);
  },

  destroyed() {
    this.cancelLongPress();
    this.clearArrowState();
    this.boardFitObserver?.disconnect();
    if (this.fitBoard) window.removeEventListener("resize", this.fitBoard);
    document.removeEventListener("openchesslab:clear-annotations", this.clearPending);
    this.clearPendingShapes();
    this.clearPendingMoves();
    this.el.removeEventListener("click", this.squareClick, true);
    this.el.removeEventListener("pointerdown", this.pointerDown);
    this.el.removeEventListener("pointermove", this.pointerMove);
    this.el.removeEventListener("pointerup", this.pointerUp);
    this.el.removeEventListener("pointercancel", this.pointerCancel);
    this.el.removeEventListener("click", this.suppressDraggedClick, true);
    this.el.removeEventListener("keydown", this.keyDown);
    this.el.removeEventListener("contextmenu", this.contextMenu);
    this.removeDrawingPreview();
    this.clearDragPreview();
  },

  updated() {
    this.fitBoard?.();

    // LiveView patches re-render the squares, which drops the client-side
    // arrow-draft marker; restore it (or clean it up) after each patch.
    if (this.arrowStart !== null) {
      this.showArrowState(this.arrowStart);
    } else {
      this.clearArrowState();
    }

    this.confirmPendingMoves();
    this.reconcileSpecSelection();
    this.reconcilePendingShapes();
    this.renderKeyboardArrowPreview();
  },

  // Touch/pen have no right-click, so a long press starts the same drawing
  // gesture (single square = highlight, drag = arrow).
  beginLongPress(square, event) {
    this.cancelLongPress();
    const color = this.el.dataset.annotationColor || "blue";
    const timer = window.setTimeout(() => {
      this.longPress = null;
      this.drag = null;
      delete this.el.dataset.dragging;
      this.clearDragPreview();
      this.drawing = {
        from: square,
        color,
        x: event.clientX,
        y: event.clientY,
        moved: false,
      };
      navigator.vibrate?.(10);
    }, 350);
    this.longPress = { square, x: event.clientX, y: event.clientY, timer };
  },

  cancelLongPress() {
    if (this.longPress) {
      window.clearTimeout(this.longPress.timer);
      this.longPress = null;
    }
  },

  // Keyboard arrows: A starts at the focused square, A again (or Enter) finishes
  // at the new square, A on the same square cancels.
  toggleArrow(square) {
    if (this.arrowStart === null) {
      this.arrowStart = square;
      this.showArrowState(square);
      this.renderKeyboardArrowPreview();
      return;
    }

    if (this.arrowStart === square) {
      this.cancelArrow();
      return;
    }

    this.finishArrow(square);
  },

  finishArrow(square) {
    const from = this.arrowStart;

    // push first: the optimistic shape is cloned from the live preview
    if (from !== null && square !== null && from !== square) {
      this.pushAnnotation({
        type: "arrow",
        from,
        to: square,
        color: this.el.dataset.annotationColor || "blue",
      });
    }

    this.cancelArrow();
  },

  cancelArrow() {
    this.arrowStart = null;
    this.clearArrowState();
    this.removeDrawingPreview();
  },

  showArrowState(square) {
    document.body.dataset.boardArrow = "armed";

    this.el
      .querySelectorAll("[data-arrow-start]")
      .forEach((el) => delete el.dataset.arrowStart);
    this.el
      .querySelector(`[data-square="${square}"]`)
      ?.setAttribute("data-arrow-start", "true");

    const hint = document.querySelector("[data-arrow-hint] [data-arrow-from]");
    if (hint) hint.textContent = this.squareName(square);
  },

  clearArrowState() {
    delete document.body.dataset.boardArrow;
    this.el
      .querySelectorAll("[data-arrow-start]")
      .forEach((el) => delete el.dataset.arrowStart);
  },

  squareName(square) {
    return "abcdefgh"[square % 8] + (Math.floor(square / 8) + 1);
  },

  squareAt(target) {
    const square = target?.closest?.("[data-square]")?.dataset.square;
    return square === undefined ? null : Number(square);
  },

  annotationColor(event) {
    const current = this.el.dataset.annotationColor || "blue";
    const index = COLORS.indexOf(current);
    if (event.altKey) return COLORS[(index + 1) % COLORS.length];
    if (event.shiftKey)
      return COLORS[(index + COLORS.length - 1) % COLORS.length];
    return current;
  },

  renderDrawingPreview(clientX, clientY) {
    if (!this.drawing) return;
    const targetSquare = this.squareAt(
      document.elementFromPoint(clientX, clientY),
    );

    if (targetSquare === null || targetSquare === this.drawing.from) {
      this.removeDrawingPreview();
      return;
    }

    this.renderArrowPreview(
      this.drawing.from,
      targetSquare,
      this.drawing.color,
    );
  },

  renderKeyboardArrowPreview() {
    if (this.arrowStart === null || this.drawing) return;
    const targetSquare = this.squareAt(document.activeElement);

    if (targetSquare === null || targetSquare === this.arrowStart) {
      this.removeDrawingPreview();
      return;
    }

    this.renderArrowPreview(
      this.arrowStart,
      targetSquare,
      this.el.dataset.annotationColor || "blue",
    );
  },

  renderArrowPreview(from, to, colorName) {
    const grid = this.el.querySelector("[data-board-grid]");
    const fromSquare = this.el.querySelector(`[data-square="${from}"]`);
    const toSquare = this.el.querySelector(`[data-square="${to}"]`);
    if (!grid || !fromSquare || !toSquare || from === to) {
      this.removeDrawingPreview();
      return;
    }

    let svg = this.el.querySelector("[data-drawing-preview]");
    if (!svg) {
      const namespace = "http://www.w3.org/2000/svg";
      svg = document.createElementNS(namespace, "svg");
      svg.dataset.drawingPreview = "true";
      svg.setAttribute("viewBox", "0 0 800 800");
      svg.setAttribute("preserveAspectRatio", "none");
      Object.assign(svg.style, {
        position: "absolute",
        inset: "0",
        width: "100%",
        height: "100%",
        overflow: "visible",
        pointerEvents: "none",
        zIndex: "30",
      });
      const line = document.createElementNS(namespace, "line");
      line.dataset.previewLine = "true";
      line.setAttribute("stroke-width", "10");
      line.setAttribute("stroke-linecap", "round");
      line.setAttribute("opacity", ".88");
      const head = document.createElementNS(namespace, "polygon");
      head.dataset.previewHead = "true";
      head.setAttribute("opacity", ".88");
      svg.append(line, head);
      grid.append(svg);
    }

    const gridRect = grid.getBoundingClientRect();
    const startRect = fromSquare.getBoundingClientRect();
    const x1 =
      ((startRect.left + startRect.width / 2 - gridRect.left) /
        gridRect.width) *
      800;
    const y1 =
      ((startRect.top + startRect.height / 2 - gridRect.top) /
        gridRect.height) *
      800;
    const endRect = toSquare.getBoundingClientRect();
    const x2 =
      ((endRect.left + endRect.width / 2 - gridRect.left) / gridRect.width) *
      800;
    const y2 =
      ((endRect.top + endRect.height / 2 - gridRect.top) / gridRect.height) *
      800;
    const color = this.shapeColor(colorName);
    const line = svg.querySelector("[data-preview-line]");
    const head = svg.querySelector("[data-preview-head]");
    line.setAttribute("x1", x1);
    line.setAttribute("y1", y1);
    line.setAttribute("x2", x2);
    line.setAttribute("y2", y2);
    line.setAttribute("stroke", color);
    head.setAttribute("fill", color);

    const angle = Math.atan2(y2 - y1, x2 - x1);
    const length = 30;
    const halfWidth = 17;
    const baseX = x2 - Math.cos(angle) * length;
    const baseY = y2 - Math.sin(angle) * length;
    const leftX = baseX + Math.sin(angle) * halfWidth;
    const leftY = baseY - Math.cos(angle) * halfWidth;
    const rightX = baseX - Math.sin(angle) * halfWidth;
    const rightY = baseY + Math.cos(angle) * halfWidth;
    head.setAttribute(
      "points",
      `${x2},${y2} ${leftX},${leftY} ${rightX},${rightY}`,
    );
  },

  startDragPreview(from, clientX, clientY) {
    const grid = this.el.querySelector("[data-board-grid]");
    const source = this.el.querySelector(`[data-square="${from}"]`);
    const piece = source?.querySelector("[data-piece]");
    if (!grid || !source || !piece) return;

    source.dataset.dragSource = "true";
    this.clearDragPreview(from);

    this.dragGhost = this.ghostFor(piece);
    grid.append(this.dragGhost);

    this.renderDragPreview(clientX, clientY);
  },

  renderDragPreview(clientX, clientY) {
    const grid = this.el.querySelector("[data-board-grid]");
    const ghost = this.dragGhost;
    if (!grid || !ghost) return;
    const rect = grid.getBoundingClientRect();
    ghost.style.left = `${clientX - rect.left}px`;
    ghost.style.top = `${clientY - rect.top}px`;
  },

  // Ends the pointer-following preview of an active drag. Never touches a
  // pending move's hold: those survive until the server confirms (the patch
  // shows the piece on the target) or rejects (the reply settles) the move.
  clearDragPreview(from) {
    if (this.dragGhost) {
      this.dragGhost.remove();
      this.dragGhost = null;
    }
    if (
      from !== undefined &&
      from !== null &&
      !this.pendingMoves.some((move) => move.from === from)
    ) {
      this.el
        .querySelector(`[data-square="${from}"]`)
        ?.removeAttribute("data-drag-source");
    }
  },

  ghostFor(piece) {
    const ghost = document.createElement("span");
    ghost.dataset.dragGhost = "true";
    Object.assign(ghost.style, {
      position: "absolute",
      width: "12.5%",
      height: "12.5%",
      display: "grid",
      placeItems: "center",
      pointerEvents: "none",
      transform: "translate(-50%, -50%)",
      zIndex: "40",
    });
    const clone = piece.cloneNode(true);
    clone.setAttribute("aria-hidden", "true");
    ghost.append(clone);
    return ghost;
  },

  // Optimistically holds the piece on the target and pushes the move. Moves
  // can pile up: each holds its own ghost (with the piece it moved), hides
  // only its own source square, and settles independently. The LiveView
  // processes the pushed events in order, so every move is validated against
  // the moves before it; the client never decides legality.
  playMove(eventName, payload, from, to, opts = {}) {
    const move = this.beginPendingMove(from, to, opts);
    if (!move) return;
    this.specSelect = null;
    this.markSpecSelect(null);
    this.pushEvent(eventName, payload, () => this.settlePendingMove(move.key));
  },

  beginPendingMove(from, to, opts = {}) {
    const grid = this.el.querySelector("[data-board-grid]");
    const source = this.el.querySelector(`[data-square="${from}"]`);
    const target = this.el.querySelector(`[data-square="${to}"]`);
    if (!grid || !source || !target) return null;

    const key = `${from}-${to}`;
    if (this.pendingMoves.some((move) => move.key === key)) return null;

    let ghost;
    if (opts.reuseDragGhost && this.dragGhost) {
      ghost = this.dragGhost;
    } else {
      this.dragGhost?.remove();
      const piece = source.querySelector("[data-piece]");
      if (!piece) return null;
      ghost = this.ghostFor(piece);
    }
    this.dragGhost = null;

    ghost.dataset.pendingMove = key;
    ghost.dataset.dragPending = "true";
    grid.append(ghost);

    source.dataset.dragSource = "true";
    this.snapGhost(ghost, grid, target);

    const move = { key, from, to, ghost, timer: null, settled: false };
    // Safety net: a reply that never arrives (dropped connection) must not
    // leave a speculative piece on the board forever.
    move.timer = window.setTimeout(() => this.settlePendingMove(key), 12000);
    this.pendingMoves.push(move);
    return move;
  },

  snapGhost(ghost, grid, target) {
    const gridRect = grid.getBoundingClientRect();
    const targetRect = target.getBoundingClientRect();
    ghost.style.left = `${targetRect.left - gridRect.left + targetRect.width / 2}px`;
    ghost.style.top = `${targetRect.top - gridRect.top + targetRect.height / 2}px`;
  },

  // The reply to this move's push arrived (or the safety net fired). The
  // diff was applied first, but a later in-flight push still holds the board
  // locked (hook pushes lock their element for the event's duration), so the
  // board may not reflect this move yet. While any later move is still
  // awaiting its reply, the deferred patches — and this move's fate — resolve
  // when the last reply unlocks the board. Only once every reply has arrived
  // does an unreflected move mean it was not played (rejected, conflict, or
  // a promotion choice is showing), and the speculative visuals roll back to
  // the server's board.
  settlePendingMove(key) {
    const move = this.pendingMoves.find((pending) => pending.key === key);
    if (move) move.settled = true;

    this.confirmPendingMoves();

    if (this.pendingMoves.some((pending) => !pending.settled)) return;

    this.clearPendingMoves();
  },

  removePendingMove(move) {
    this.pendingMoves = this.pendingMoves.filter((pending) => pending !== move);
    window.clearTimeout(move.timer);
    move.ghost.remove();
    this.unmarkSource(move.from);
  },

  clearPendingMoves() {
    for (const move of [...this.pendingMoves]) this.removePendingMove(move);
  },

  // Only this move's source square: another pending move may still be
  // holding its piece hidden on the same square.
  unmarkSource(from) {
    if (this.pendingMoves.some((move) => move.from === from)) return;
    this.el
      .querySelector(`[data-square="${from}"]`)
      ?.removeAttribute("data-drag-source");
  },

  // Reconciles the optimistic holds with the server-rendered board after a
  // patch: a pending move whose target now shows a piece while its source is
  // empty has become authoritative, so its optimistic marks can go. The
  // others are re-applied, because patches re-render squares (dropping the
  // JS-set ghost and source marker) and can resize the board.
  confirmPendingMoves() {
    const grid = this.el.querySelector("[data-board-grid]");

    for (const move of [...this.pendingMoves]) {
      const source = this.el.querySelector(`[data-square="${move.from}"]`);
      const target = this.el.querySelector(`[data-square="${move.to}"]`);

      if (
        target?.querySelector("[data-piece]") &&
        !source?.querySelector("[data-piece]")
      ) {
        this.removePendingMove(move);
        continue;
      }

      if (source) source.dataset.dragSource = "true";
      if (grid && target) {
        if (!move.ghost.isConnected) grid.append(move.ghost);
        this.snapGhost(move.ghost, grid, target);
      }
    }
  },

  playMode() {
    // The server renders data-play only while square clicks play moves;
    // the position editor and the setup board keep their native flows.
    return this.el.dataset.play !== undefined;
  },

  // The side to move including unconfirmed moves: every pending move flips
  // it. Recomputed from the server-rendered attribute so it self-corrects.
  specSideToMove() {
    const side = this.el.dataset.sideToMove;
    if (side !== "white" && side !== "black") return null;
    if (this.pendingMoves.length % 2 === 0) return side;
    return side === "white" ? "black" : "white";
  },

  selectableSpecPiece(square) {
    const squareEl = this.el.querySelector(`[data-square="${square}"]`);
    const piece = squareEl?.querySelector("[data-piece]");
    if (!piece) return null;
    const side = this.specSideToMove();
    if (!side || piece.dataset.pieceColor === side) return square;
    return null;
  },

  markSpecSelect(square) {
    this.el
      .querySelectorAll("[data-spec-selected]")
      .forEach((el) => delete el.dataset.specSelected);
    if (square !== null && square !== undefined) {
      this.el
        .querySelector(`[data-square="${square}"]`)
        ?.setAttribute("data-spec-selected", "true");
    }
  },

  // The server's own selection patch is authoritative: adopt it (a fast
  // target click then uses the server-confirmed source). Without one, keep
  // the local selection only while its piece is still on the board, and
  // re-apply the marker (patches re-render squares and drop JS-set attrs).
  reconcileSpecSelection() {
    const serverSelected = this.el.querySelector("[data-square][aria-pressed]");
    if (serverSelected) {
      this.specSelect = Number(serverSelected.dataset.square);
      // the server renders its own selection highlight
      this.markSpecSelect(null);
      return;
    }

    if (
      this.specSelect !== null &&
      !this.el.querySelector(`[data-square="${this.specSelect}"] [data-piece]`)
    ) {
      this.specSelect = null;
    }

    this.markSpecSelect(this.specSelect);
  },

  // Annotations: keep the local shape until the server renders it, so arrows
  // and highlights don't blink out during the round trip.
  pushAnnotation(payload) {
    const key =
      payload.type === "arrow"
        ? `arrow-${payload.from}-${payload.to}-${payload.color}`
        : `square-${payload.square}-${payload.color}`;

    // If the server already renders this shape, this is a removal: don't add
    // an optimistic copy.
    if (!this.el.querySelector(`[data-shape-key="${key}"]`)) {
      this.addPendingShape(key, payload);
    }

    this.pushEvent("board-annotation", payload);
  },

  addPendingShape(key, payload) {
    if (this.pendingShapes.some((shape) => shape.key === key)) return;
    const grid = this.el.querySelector("[data-board-grid]");
    if (!grid) return;

    let el = null;

    if (payload.type === "arrow") {
      const preview = this.el.querySelector("[data-drawing-preview]");
      if (!preview) return;
      el = preview.cloneNode(true);
      el.removeAttribute("data-drawing-preview");
    } else {
      const file = payload.square % 8;
      const rank = Math.floor(payload.square / 8);
      const black = this.el.dataset.orientation === "black";
      el = document.createElement("div");
      Object.assign(el.style, {
        position: "absolute",
        left: `${(black ? 7 - file : file) * 12.5}%`,
        top: `${(black ? rank : 7 - rank) * 12.5}%`,
        width: "12.5%",
        height: "12.5%",
        border: `5px solid ${this.shapeColor(payload.color)}`,
        pointerEvents: "none",
        zIndex: "10",
        boxSizing: "border-box",
      });
    }

    el.dataset.pendingShape = key;
    grid.append(el);
    this.pendingShapes.push({
      key,
      el,
      timer: window.setTimeout(() => this.clearPendingShape(key), 8000),
    });
  },

  clearPendingShape(key) {
    const index = this.pendingShapes.findIndex((shape) => shape.key === key);
    if (index === -1) return;
    const [shape] = this.pendingShapes.splice(index, 1);
    window.clearTimeout(shape.timer);

    // LiveView's morph can reuse our optimistic node as the real server shape
    // (it then carries data-shape-key and lost the pending marker). Only
    // remove the node while it is still the pending copy.
    if (shape.el.dataset.pendingShape) shape.el.remove();
  },

  clearPendingShapes() {
    for (const shape of [...this.pendingShapes]) this.clearPendingShape(shape.key);
  },

  reconcilePendingShapes() {
    for (const shape of [...this.pendingShapes]) {
      if (this.el.querySelector(`[data-shape-key="${shape.key}"]`)) {
        this.clearPendingShape(shape.key);
      } else if (!shape.el.isConnected) {
        this.el.querySelector("[data-board-grid]")?.append(shape.el);
      }
    }
  },

  removeDrawingPreview() {
    this.el.querySelector("[data-drawing-preview]")?.remove();
  },

  shapeColor(color) {
    return (
      {
        yellow: "#f2c200",
        blue: "#3b6fe0",
        red: "#d6453d",
        orange: "#e08a1e",
        purple: "#8b5cf6",
      }[color] || "#3b6fe0"
    );
  },
};

const ScrollLog = {
  mounted() {
    this.scrollToBottom = () => {
      this.el.scrollTop = this.el.scrollHeight;
    };

    // The chat panel can start hidden (mobile tab) with a zero-height log, so
    // jump to the newest message as soon as it becomes visible.
    this.lastHeight = this.el.clientHeight;
    this.observer = new ResizeObserver(() => {
      const height = this.el.clientHeight;
      if (height > 0 && this.lastHeight === 0) {
        this.stick = true;
        this.scrollToBottom();
      }
      this.lastHeight = height;
    });
    this.observer.observe(this.el);

    // Track whether the reader is pinned to the bottom *before* new messages
    // arrive; measuring afterwards fails for messages taller than the threshold.
    this.stick = true;
    this.onScroll = () => {
      const remaining =
        this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight;
      this.stick = remaining < 48;
    };
    this.el.addEventListener("scroll", this.onScroll);

    this.scrollToBottom();
  },

  updated() {
    const last = this.el.querySelector("article:last-of-type");
    const mine = last && last.classList.contains("self-end");

    // always follow your own message; follow others when already at the bottom
    if (mine || this.stick) this.scrollToBottom();
  },

  destroyed() {
    this.observer?.disconnect();
    this.el.removeEventListener("scroll", this.onScroll);
  },
};

const EvalBar = {
  mounted() {
    this.findBoard = () =>
      this.el
        .closest("[data-tour='board']")
        ?.querySelector("#chess-board [data-board-grid]");

    this.syncHeight = () => {
      const board = this.findBoard();

      if (board !== this.board) {
        this.resizeObserver?.disconnect();
        this.board = board;
        if (this.board) this.resizeObserver?.observe(this.board);
      }

      if (this.board) {
        this.el.style.height = `${this.board.getBoundingClientRect().height}px`;
      }
    };

    this.resizeObserver = new ResizeObserver(this.syncHeight);
    this.syncHeight();
  },

  updated() {
    this.syncHeight();
  },

  destroyed() {
    this.resizeObserver?.disconnect();
  },
};

const RoomTabs = {
  mounted() {
    this.tabKey = "openchesslab:room-tab";
    this.sizeKey = "openchesslab:room-panel-size";

    this.setTab = (tab) => {
      document.body.dataset.roomTab = tab;
      for (const button of this.el.querySelectorAll("[data-tab]")) {
        const active = button.dataset.tab === tab;
        button.setAttribute("aria-selected", active ? "true" : "false");
      }
      try {
        localStorage.setItem(this.tabKey, tab);
      } catch (_) {
        /* optional */
      }
    };

    this.setPanelSize = (size) => {
      document.body.dataset.roomPanelSize = size;
      try {
        localStorage.setItem(this.sizeKey, size);
      } catch (_) {
        /* optional */
      }
    };

    this.onClick = (event) => {
      const tab = event.target.closest("[data-tab]");
      if (tab && this.el.contains(tab)) {
        this.setTab(tab.dataset.tab);
        return;
      }
      if (event.target.closest("#room-panel-size")) {
        this.setPanelSize(
          document.body.dataset.roomPanelSize === "roomy" ? "big" : "roomy",
        );
      }
    };
    this.el.addEventListener("click", this.onClick);

    let tab = "moves";
    let size = "big";
    try {
      tab = localStorage.getItem(this.tabKey) || "moves";
      size = localStorage.getItem(this.sizeKey) || "big";
    } catch (_) {
      /* optional */
    }

    this.setTab(["moves", "games", "chat"].includes(tab) ? tab : "moves");
    this.setPanelSize(size === "roomy" ? "roomy" : "big");
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick);
    delete document.body.dataset.roomTab;
    delete document.body.dataset.roomPanelSize;
  },
};

const PaletteDrag = {
  mounted() {
    this.ghost = null;
    this.drag = null;
    this.grab = null;

    this.onPointerDown = (event) => {
      const button = event.target.closest("[data-piece-code]");
      if (!button || event.button !== 0) return;
      const rect = button.getBoundingClientRect();
      this.drag = {
        piece: button.dataset.pieceCode,
        x: event.clientX,
        y: event.clientY,
        started: false,
      };
      this.grab = { w: rect.width, h: rect.height, html: button.innerHTML };
      button.setPointerCapture?.(event.pointerId);
    };

    this.onPointerMove = (event) => {
      if (!this.drag) return;
      if (!this.drag.started) {
        const travelled =
          Math.abs(event.clientX - this.drag.x) +
          Math.abs(event.clientY - this.drag.y);
        if (travelled < 6) return;
        this.drag.started = true;
        this.showGhost();
      }
      this.positionGhost(event.clientX, event.clientY);
    };

    this.onPointerUp = (event) => {
      if (!this.drag) return;
      const drag = this.drag;
      this.drag = null;
      this.removeGhost();
      if (!drag.started) return; // plain tap: the button's phx-click arms the piece

      const squareButton = document
        .elementFromPoint(event.clientX, event.clientY)
        ?.closest("[data-square]");
      if (!squareButton) return;

      const board = squareButton.closest("#setup-board, #chess-board");
      const name =
        board && board.id === "setup-board"
          ? "setup-palette-drop"
          : "palette-drop";
      this.pushEvent(name, {
        piece: drag.piece,
        square: squareButton.dataset.square,
      });
    };

    this.onPointerCancel = () => {
      this.drag = null;
      this.removeGhost();
    };

    this.el.addEventListener("pointerdown", this.onPointerDown);
    this.el.addEventListener("pointermove", this.onPointerMove);
    this.el.addEventListener("pointerup", this.onPointerUp);
    this.el.addEventListener("pointercancel", this.onPointerCancel);
  },

  destroyed() {
    this.el.removeEventListener("pointerdown", this.onPointerDown);
    this.el.removeEventListener("pointermove", this.onPointerMove);
    this.el.removeEventListener("pointerup", this.onPointerUp);
    this.el.removeEventListener("pointercancel", this.onPointerCancel);
    this.removeGhost();
  },

  showGhost() {
    if (this.ghost) return;
    const ghost = document.createElement("div");
    ghost.dataset.paletteGhost = "true";
    Object.assign(ghost.style, {
      position: "fixed",
      width: `${this.grab.w}px`,
      height: `${this.grab.h}px`,
      display: "grid",
      placeItems: "center",
      pointerEvents: "none",
      zIndex: "80",
      opacity: ".85",
    });
    ghost.innerHTML = this.grab.html;
    document.body.append(ghost);
    this.ghost = ghost;
  },

  positionGhost(clientX, clientY) {
    if (!this.ghost) return;
    this.ghost.style.left = `${clientX - this.grab.w / 2}px`;
    this.ghost.style.top = `${clientY - this.grab.h / 2}px`;
  },

  removeGhost() {
    this.ghost?.remove();
    this.ghost = null;
  },
};

const MoveList = {
  mounted() {
    this.keepCurrentMoveVisible = () => {
      const current = this.el.querySelector('[aria-current="location"]');

      if (!current) {
        this.el.scrollTo?.({ top: 0 });
        return;
      }

      const listRect = this.el.getBoundingClientRect();
      const moveRect = current.getBoundingClientRect();

      if (moveRect.top < listRect.top) {
        this.el.scrollTop += moveRect.top - listRect.top;
      } else if (moveRect.bottom > listRect.bottom) {
        this.el.scrollTop += moveRect.bottom - listRect.bottom;
      }
    };

    // Roving tabindex is kept client-side: a phx-focus round trip on mousedown
    // patches the button mid-click and swallows the click event.
    this.setTabstop = (button) => {
      this.el.querySelectorAll("[data-move-path]").forEach((el) => {
        el.tabIndex = el === button ? 0 : -1;
      });
    };

    this.onFocusIn = (event) => {
      const button = event.target.closest?.("[data-move-path]");
      if (button && this.el.contains(button)) this.setTabstop(button);
    };

    this.el.addEventListener("focusin", this.onFocusIn);
    this.keepCurrentMoveVisible();
  },

  updated() {
    this.keepCurrentMoveVisible();

    const focused = document.activeElement;
    if (
      focused &&
      this.el.contains(focused) &&
      focused.hasAttribute?.("data-move-path")
    ) {
      this.setTabstop(focused);
    }
  },

  destroyed() {
    this.el.removeEventListener("focusin", this.onFocusIn);
  },
};

const AppUI = {
  mounted() {
    this.handleEvent("set-theme", ({ theme }) => {
      document.documentElement.dataset.theme = theme;
      this.el.dataset.theme = theme;
      try {
        localStorage.setItem("openchesslab:theme", theme);
      } catch (_) {
        /* optional */
      }
    });

    this.handleEvent("set-locale", ({ locale }) => {
      document.documentElement.lang = locale;
      try {
        localStorage.setItem("openchesslab:locale", locale);
      } catch (_) {
        /* optional */
      }
    });

    this.handleEvent("set-piece-set", ({ piece_set }) => {
      try {
        localStorage.setItem("openchesslab:piece-set", piece_set);
      } catch (_) {
        /* optional */
      }
    });

    this.handleEvent("set-annotation-color", ({ color }) => {
      try {
        localStorage.setItem("openchesslab:annotation-color", color);
      } catch (_) {
        /* optional */
      }
    });

    this.handleEvent("set-strip-preference", ({ open, tab }) => {
      try {
        localStorage.setItem("openchesslab:strip-open", String(open));
        localStorage.setItem("openchesslab:strip-tab", tab);
      } catch (_) {
        /* optional */
      }
    });

    this.handleEvent("focus-move", ({ path }) => {
      const selector = path
        ? `[data-move-path="${path}"]`
        : `[data-move-path="0"]`;
      requestAnimationFrame(() => this.el.querySelector(selector)?.focus());
    });

    this.handleEvent("copy-text", async ({ text, notice }) => {
      try {
        const copyValue = text.startsWith("/")
          ? new URL(text, window.location.origin).toString()
          : text;
        await navigator.clipboard.writeText(copyValue);
        if (notice)
          this.pushEvent("clipboard-result", { success: true, notice });
      } catch (_) {
        this.pushEvent("clipboard-result", { success: false, notice: text });
      }
    });

    this.handleEvent("download-svg", ({ svg, filename }) => {
      const blob = new Blob([svg], { type: "image/svg+xml;charset=utf-8" });
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement("a");
      anchor.href = url;
      anchor.download = filename || "openchesslab-position.svg";
      anchor.click();
      URL.revokeObjectURL(url);
    });

    let preferences = {};
    try {
      preferences = {
        theme: localStorage.getItem("openchesslab:theme"),
        locale: localStorage.getItem("openchesslab:locale"),
        piece_set: localStorage.getItem("openchesslab:piece-set"),
        annotation_color: localStorage.getItem("openchesslab:annotation-color"),
        strip_open: localStorage.getItem("openchesslab:strip-open"),
        strip_tab: localStorage.getItem("openchesslab:strip-tab"),
      };
    } catch (_) {
      /* optional */
    }
    if (["system", "light", "dark"].includes(preferences.theme)) {
      this.el.dataset.theme = preferences.theme;
      document.documentElement.dataset.theme = preferences.theme;
    }
    if (["en", "nl"].includes(preferences.locale)) {
      document.documentElement.lang = preferences.locale;
    }
    this.pushEvent("restore-preferences", preferences);

    this.keyDown = (event) => {
      const target = event.target;
      const typing = target?.matches?.(
        "input, textarea, select, [contenteditable='true']",
      );
      if (typing || event.metaKey || event.ctrlKey || event.altKey) return;

      if (document.querySelector("[data-tour-dialog]")) {
        if (event.key === "ArrowLeft") {
          event.preventDefault();
          this.pushEvent("tour-back", {});
        } else if (event.key === "ArrowRight") {
          event.preventDefault();
          this.pushEvent("tour-next", {});
        } else if (event.key === "Escape") {
          event.preventDefault();
          this.pushEvent("close-modal", {});
        }
        return;
      }

      const moveButton = target?.closest?.("[data-move-path]");
      const board = target?.closest?.("[data-board]");

      // Shift+arrows step the mainline even while the board has focus, where
      // plain arrows move the square cursor.
      if (
        this.el.dataset.roomCode &&
        event.shiftKey &&
        (event.key === "ArrowLeft" || event.key === "ArrowRight")
      ) {
        event.preventDefault();
        this.pushEvent(
          event.key === "ArrowRight" ? "next-move" : "previous-move",
          {},
        );
        return;
      }

      if (
        moveButton &&
        ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(event.key)
      ) {
        event.preventDefault();
        this.pushEvent("move-tree-key", {
          path: moveButton.dataset.movePath,
          key: event.key,
        });
        return;
      }

      // Plain arrows step the mainline when neither the board nor the move tree
      // has focus (with the board focused they move the square cursor).
      if (
        this.el.dataset.roomCode &&
        !board &&
        !moveButton &&
        (event.key === "ArrowLeft" || event.key === "ArrowRight")
      ) {
        event.preventDefault();
        this.pushEvent(
          event.key === "ArrowRight" ? "next-move" : "previous-move",
          {},
        );
        return;
      }

      if (!board && this.el.dataset.roomCode && /^[1-5]$/.test(event.key)) {
        this.pushEvent("annotation-color", {
          color: COLORS[Number(event.key) - 1],
        });
        return;
      }

      if (event.key === "?") {
        event.preventDefault();
        this.pushEvent("open-shortcuts", {});
      } else if (event.key === "Escape") {
        this.pushEvent("close-modal", {});
      } else if (event.key.toLowerCase() === "b" && this.el.dataset.roomCode) {
        event.preventDefault();
        this.el
          .querySelector("#chess-board [data-square][tabindex='0']")
          ?.focus();
      } else if (event.key.toLowerCase() === "m" && this.el.dataset.roomCode) {
        event.preventDefault();
        const moveTarget =
          this.el.querySelector("#move-list [tabindex='0']") ||
          this.el.querySelector("#move-list");
        moveTarget?.focus();
      } else if (event.key.toLowerCase() === "f" && this.el.dataset.roomCode) {
        this.pushEvent("toggle-orientation", {});
      } else if (event.key === "Home" && this.el.dataset.roomCode) {
        this.pushEvent("first-move", {});
      } else if (event.key === "End" && this.el.dataset.roomCode) {
        this.pushEvent("last-move", {});
      } else if (event.key.toLowerCase() === "e" && this.el.dataset.roomCode) {
        this.pushEvent("toggle-engine", {});
      }
    };
    document.addEventListener("keydown", this.keyDown);

    if (this.el.dataset.roomCode) {
      this.ping = window.setInterval(() => {
        const started = performance.now();
        this.pushEvent("latency-ping", {}, () => {
          const value = Math.max(0, Math.round(performance.now() - started));
          this.el
            .querySelector("[data-latency]")
            ?.replaceChildren(`${value} ms`);
        });
      }, 10000);
    }
  },

  destroyed() {
    if (this.ping) window.clearInterval(this.ping);
    document.removeEventListener("keydown", this.keyDown);
  },
};

const csrfToken = document.querySelector("meta[name='csrf-token']")?.content;
const liveSocket = new LiveSocket("/live", Socket, {
  hooks: { AppUI, Board, EvalBar, MoveList, PaletteDrag, RoomTabs, ScrollLog },
  params: { _csrf_token: csrfToken },
});

liveSocket.connect();
window.liveSocket = liveSocket;
