"""Float reference forward pass of the darknet network (torch, CPU)."""
import numpy as np
import torch
import torch.nn.functional as F
import cv2

torch.set_grad_enabled(False)


def load_image(path, size=416):
    """Darknet-style preprocessing: RGB, plain resize (no letterbox). Returns uint8 HWC RGB."""
    img = cv2.imread(path)
    if img is None:
        raise FileNotFoundError(path)
    rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    return cv2.resize(rgb, (size, size), interpolation=cv2.INTER_LINEAR), img.shape[:2]


def to_tensor(rgb_u8):
    return torch.from_numpy(rgb_u8.astype(np.float32) / 255.0).permute(2, 0, 1)[None]


class FloatNet:
    def __init__(self, net):
        self.net = net
        self.w = {}
        for L in net['layers']:
            if L['type'] == 'convolutional':
                self.w[L['idx']] = (torch.from_numpy(L['w'].astype(np.float32)),
                                    torch.from_numpy(L['b'].astype(np.float32)))

    def forward(self, x, keep_all=False):
        """x: 1x3xHxW float tensor in [0,1]. Returns list of per-layer outputs and yolo head raw outputs."""
        outs = []
        heads = []
        for L in self.net['layers']:
            t = L['type']
            if t == 'convolutional':
                w, b = self.w[L['idx']]
                x = F.conv2d(x, w, b, stride=L['stride'], padding=L['pad'])
                if L['act'] == 'leaky':
                    x = F.leaky_relu(x, 0.1)
            elif t == 'maxpool':
                x = F.max_pool2d(x, 2, 2)
            elif t == 'route':
                parts = []
                for r in L['refs']:
                    o = outs[r]
                    if L['groups'] > 1:
                        c = o.shape[1] // L['groups']
                        o = o[:, c * L['group_id']:c * (L['group_id'] + 1)]
                    parts.append(o)
                x = torch.cat(parts, 1)
            elif t == 'upsample':
                x = F.interpolate(x, scale_factor=L['stride'], mode='nearest')
            elif t == 'yolo':
                heads.append((L, x))
            outs.append(x)
        return outs, heads
