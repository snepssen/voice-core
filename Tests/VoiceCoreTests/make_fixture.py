"""The smallest graph with a Piper voice's inputs and output.

output = float(input) * scales[1], shaped [1, N]: one inference call reads
back ids times the length scale, so a test knows the exact answer. It holds
voice-core's inference path on every platform without shipping a voice.
Run with the `onnx` package: python3 make_fixture.py <out.onnx>
"""
import sys
import onnx
from onnx import TensorProto, helper

inputs = [
    helper.make_tensor_value_info("input", TensorProto.INT64, [1, "n"]),
    helper.make_tensor_value_info("input_lengths", TensorProto.INT64, [1]),
    helper.make_tensor_value_info("scales", TensorProto.FLOAT, [3]),
]
outputs = [helper.make_tensor_value_info("output", TensorProto.FLOAT, [1, "n"])]
one = helper.make_tensor("one", TensorProto.INT64, [], [1])
nodes = [
    helper.make_node("Cast", ["input"], ["ids"], to=TensorProto.FLOAT),
    helper.make_node("Gather", ["scales", "one"], ["length_scale"], axis=0),
    helper.make_node("Mul", ["ids", "length_scale"], ["output"]),
]
graph = helper.make_graph(nodes, "piper_shape", inputs, outputs, initializer=[one])
model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 13)], ir_version=8)
onnx.checker.check_model(model)
onnx.save(model, sys.argv[1])
