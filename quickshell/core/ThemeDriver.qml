import QtQuick

// Glides Theme.accent/accentText/mid/deep toward their targets. Create exactly one (shell.qml does).
Item {
    visible: false

    property color a: Theme.tgtAccent
    property color o: Theme.tgtOn
    property color m: Theme.tgtMid
    property color d: Theme.tgtDeep

    Behavior on a { ColorAnimation { duration: Motion.tint; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.soft } }
    Behavior on o { ColorAnimation { duration: Motion.tint; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.soft } }
    Behavior on m { ColorAnimation { duration: Motion.tint; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.soft } }
    Behavior on d { ColorAnimation { duration: Motion.tint; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.soft } }

    onAChanged: Theme.accent = a
    onOChanged: Theme.accentText = o
    onMChanged: Theme.mid = m
    onDChanged: Theme.deep = d
}
